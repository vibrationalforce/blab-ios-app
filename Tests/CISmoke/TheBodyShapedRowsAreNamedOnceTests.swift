// TheBodyShapedRowsAreNamedOnceTests.swift
// Echoel — #560, REIHENFOLGE Punkt 2 ("welche Parameter das Biofeedback bewegt"), the inverse
// direction.
//
// WHAT THIS IS ABOUT. #553 answered "what is my body doing?" where the promise is made — the Bio
// panel, four live channel rows. The question a player actually asks arrives somewhere else: they
// are in Sound & texture, a number they set is drifting, and they want to know which of THESE
// controls the body moves. Until this slice the app could only answer forwards
// (coherence → filter · brightness · harmonicity · noise), because the mapping existed solely as
// a `· `-joined display string. #560 turns it into a set, derives the old string from it, and
// puts one sentence on the Sound panel.
//
// ⚠️ THE REGRESSION RISK IS THE COPY, NOT THE MODEL, and claim 1 is the assertion that matters.
// `AlwaysOnBioChannel.shapes` is rendered to a user in TWO places (the FX sheet's
// `AlwaysOnBioView` and, since #553, the Bio panel strip). Rewriting it as a derivation is
// exactly the kind of refactor that silently changes a separator, an order, or one word — and
// this particular string has already had to be corrected twice for what it CLAIMS ABOUT THE BODY
// (#496 over-claiming three channels with no producer, #546 naming a reverb stage that cannot
// sound). So all four channel strings are pinned character for character.
//
// ⚠️ THE LIMIT, PER ASSERTION:
//   · claims 1–3 are END-TO-END BEHAVIOUR — `AlwaysOnBioChannel` and `BioShapedParameter` are
//     public Foundation-only value types, so these drive the shipped strings.
//   · claim 4 is MIXED and it is the one worth having: it takes the row labels the sentence
//     prints and looks for each of them in `soundPanel`'s actual source. A sentence that names
//     a row nobody can find is worse than no sentence.
//   · claim 5 is a SOURCE-TEXT SCAN (mount + the freeze counterweight).
//   · DEVICE PROBE, open: whether the sentence reads as an explanation rather than as noise at
//     the top of an already-long panel, and whether a player who sees "Brightness" drift
//     actually connects it to the line. Nothing here renders anything.
//
// ⚠️ HONEST GRADING. **This file does not compile against the parent (`cc41e8b`)** — claims 2–4
// name `BioShapedParameter`, which this commit creates. No assertion has a verdict there, and
// writing "zero regressions" would be the #488 ambiguity. Transcribed in Python against both
// trees instead (§0 of `Tests/CISmoke/CLAUDE.md`):
//   · claim 1 is a COUNTERWEIGHT and the point of the file: the four strings are byte-identical
//     on both trees. Written as `XCTAssertEqual` against literals rather than against the old
//     source, because the question is whether the SHIPPED WORDS changed, and the parent's
//     literals are what shipped.
//   · claims 2–4 are FORWARD guards over a type that does not exist on the parent — ONE absence,
//     three assertions, ONE finding (#486).
//   · claim 5 splits: the mount is a REGRESSION (absent on the parent), the freeze half is a
//     COUNTERWEIGHT green on both.
//   · STRIPPER: **PROPHYLAKTISCH, 0 of 16 verdicts flip** (8 needles × 2 trees).
//
// ⛔ AND I WROTE "TRAGEND, 2 of 8" HERE FIRST — THE SECOND CONSECUTIVE SLICE TO GUESS THAT LINE,
// one cycle after #559's header records the identical mistake and names it. The reasoning was
// again plausible and again untested: the mount comment explains that nothing on this panel reads
// bio, so surely it contains `latestBio` raw and trips the negative needle. It does not — it says
// "reads bio", not the symbol. Measured: every one of the 16 verdicts agrees raw and stripped.
//
// ⭐ TWICE IS NOT A SLIP, IT IS THE SHAPE OF THE MISTAKE, so it is worth stating exactly. The
// grading block is written LAST, when the slice already feels finished, and by then I have a
// strong prior about my own comments — six #486/#491 collisions in this session made "the prose
// will contain the needle" feel like a property of the repo rather than a claim about one file.
// It is a claim about one file. The rule that follows: **the stripper line is not written until
// the transcription that produces it has been run**, in the same way a count is not written until
// `git ls-files` has. `SourceText.codeOnly` stays (#453, one definition of "code, not prose") and
// becomes load-bearing the day someone writes a retraction here quoting a form these scans look
// for — which is precisely how it became load-bearing in `TheAlwaysOnRowsReachTheBioPanelTests`.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBodyShapedRowsAreNamedOnceTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - claim 1 (COUNTERWEIGHT) — the derivation changed no shipped word

    func testTheChannelRowsStillReadExactlyAsTheyShipped() {
        let expected: [AlwaysOnBioChannel: String] = [
            .coherence:   "filter · brightness · harmonicity · noise",
            .hrv:         "brightness",
            .heartRate:   "vibrato · brightness",
            .breathPhase: "level"
        ]
        for channel in AlwaysOnBioChannel.allCases {
            XCTAssertEqual(channel.shapes, expected[channel], """
                `\(channel.rawValue).shapes` reads "\(channel.shapes)" instead of \
                "\(expected[channel] ?? "—")". #560 rewrote this from four literals into \
                `shapedParameters.map(\\.channelWord).joined(separator: " · ")`, and this string \
                is rendered to a user in two places (the FX sheet's `AlwaysOnBioView` and the \
                Bio panel strip). A changed separator, order or word here is a changed claim \
                about the body — the thing this exact string has already had to be corrected \
                for twice (#496, #546). If a channel genuinely stopped shaping a parameter, \
                change this expectation deliberately and move the file header with it.
                """)
        }
    }

    // MARK: - claim 2 (END-TO-END) — the inverse set is derived, never listed twice

    /// The whole reason `BioShapedParameter` exists is that the forward and inverse readings
    /// must be the same fact. A hand-maintained inverse list is the #416 defect with a delay
    /// fuse: it agrees today and drifts the first time a channel's mapping is corrected.
    func testTheInverseSetIsExactlyWhatTheChannelsWrite() {
        let fromChannels = Set(AlwaysOnBioChannel.allCases.flatMap(\.shapedParameters))
        let inverse = Set(BioShapedParameter.shapedByTheBody)
        XCTAssertEqual(inverse, fromChannels, """
            `shapedByTheBody` is \(inverse.map(\.rawValue).sorted()) while the channels write \
            \(fromChannels.map(\.rawValue).sorted()). These must be the same set by \
            construction — if the inverse ever has to be listed by hand, the Sound panel and \
            the Bio panel start describing different engines.
            """)
        XCTAssertFalse(inverse.isEmpty, """
            No parameter at all is reported as body-shaped. `applyBioReactive` writes \
            brightness, cutoff, harmonicity, noise, vibrato and amplitude from live channels; \
            an empty set here would print the "not shaping any control" fallback on a panel \
            where the body IS moving five rows.
            """)
        XCTAssertEqual(BioShapedParameter.shapedByTheBody,
                       BioShapedParameter.allCases.filter { inverse.contains($0) }, """
            `shapedByTheBody` is not in declaration order. That order is the Sound panel's \
            top-to-bottom order, and a player reads the sentence against the panel — scrambling \
            it makes the line harder to check than the panel it describes.
            """)
    }

    // MARK: - claim 3 (END-TO-END) — the sentence names rows, and not the one that is a trap

    /// ⛔ THE `amplitude` CASE IS THE TRAP THIS ASSERTION EXISTS FOR. Breath phase shapes
    /// `EchoelDDSP.amplitude` — the envelope inside the voice — and the Level group's "Output"
    /// row is `SynthPatch.outputLevel`, a per-patch loudness trim `applyBioReactive` never
    /// touches. Deriving the sentence from the channel words alone would have printed "level",
    /// and a player would have gone looking for the one row on this panel the body does NOT
    /// move. Same class as #496: naming something the engine does not do.
    func testTheSentenceNamesEveryLiveRowAndNoDeadOne() {
        // #640 made the subject an argument. `false` is the ORDINARY path — a real measured
        // body, or none arriving — and it is the path every assertion in this file was written
        // about: the row NAMES must be identical in both variants, and only the demo variant's
        // subject differs. The synthetic variant is guarded by
        // `TheSoundPanelNamesItsActualDriverTests`, which also pins that the row list is shared.
        let sentence = BioShapedParameter.soundPanelSentence(synthetic: false)
        for parameter in BioShapedParameter.shapedByTheBody {
            for row in parameter.soundPanelRows {
                XCTAssertTrue(sentence.contains(row), """
                    The Sound-panel line does not name "\(row)", which \
                    `\(parameter.rawValue)` says is its row on that panel. The sentence is \
                    built from exactly these labels; a missing one means a control the body \
                    moves is left unexplained on the screen it moves on.
                    """)
            }
        }
        XCTAssertTrue(BioShapedParameter.amplitude.soundPanelRows.isEmpty, """
            `amplitude` now claims a Sound-panel row. The breath swell rides the voice's \
            envelope; the panel's "Output" row is `SynthPatch.outputLevel`, a loudness trim the \
            always-on path never writes. If a row genuinely became body-shaped, name it — but \
            check which property `applyBioReactive` assigns first, because "Output" is the \
            wrong answer for the right-sounding reason.
            """)
        XCTAssertFalse(sentence.contains("Output"), """
            The Sound-panel line names "Output". See above — that row is not body-shaped, and \
            pointing a player at a control that does not move is the #496 defect arriving on a \
            different panel.
            """)
        XCTAssertTrue(sentence.contains("Open Bio"), """
            The line no longer points at the Bio panel. It deliberately does NOT show live \
            values — the live half is `AlwaysOnBioPanelStrip` (#553), and duplicating it here \
            would be two readouts free to disagree about whether a channel is measured or held \
            (#416). Without the pointer the sentence states a fact the player cannot check.
            """)
    }

    // MARK: - claim 4 (MIXED) — every named row exists on the panel it names

    /// The assertion that turns the sentence from copy into a claim. A label typo, or a row
    /// renamed in `soundPanel` without touching the model, leaves a sentence pointing at a
    /// control that is not there — and nothing else in the tree would notice.
    func testEveryRowTheSentenceNamesExistsInTheSoundPanel() throws {
        let body = try soundPanelBody()
        for parameter in BioShapedParameter.shapedByTheBody {
            for row in parameter.soundPanelRows {
                XCTAssertTrue(body.contains("\"\(row)\""), """
                    `soundPanel` has no control labelled "\(row)", which the body-shaped line \
                    names. Either the row was renamed — then rename it in \
                    `BioShapedParameter.soundPanelRows` in the SAME commit (#456) — or the \
                    label was mistyped, and the sentence has been sending players to look for \
                    a control that does not exist.
                    """)
            }
        }
    }

    // MARK: - claim 5 (REGRESSION + COUNTERWEIGHT) — mounted, and observing nothing

    func testTheSoundPanelMountsTheLineAndStillReadsNoBio() throws {
        let code = try codeText(Self.studio)
        // ⛔ RE-ANCHORED IN #640, TWO HOPS INSTEAD OF ONE, and the second hop is why: the
        // panel no longer names the sentence directly — it mounts `BodyShapesThisSoundLine`,
        // which reads bio in its own body so the host stays a non-observer. Checking only for
        // the mount would go green on a leaf that renders anything at all; checking only for
        // the sentence would go red on the correct code. Both, or the chain is not proven.
        XCTAssertTrue(code.contains("BodyShapesThisSoundLine()"), """
            Nothing in `\(Self.studio)` mounts `BodyShapesThisSoundLine`. The rows on that \
            panel are ANCHORS the body moves around, and without the line the panel presents \
            them as final values — which is the misunderstanding #556's law is about, arriving \
            at the player instead of at the next developer.
            """)
        let leaf = try codeText("Sources/Echoelmusic/Studio/BodyShapesThisSoundLine.swift")
        XCTAssertTrue(leaf.contains("BioShapedParameter.soundPanelSentence("), """
            `BodyShapesThisSoundLine` no longer renders `soundPanelSentence`. The mount above \
            then proves only that SOMETHING is on the panel — re-anchor both hops in the same \
            commit, or the assertion is green about a chain that no longer arrives.
            """)
        let body = try soundPanelBody()
        XCTAssertFalse(body.contains("latestBio"), """
            `soundPanel`'s own body reads a bio value. It is reached through `dropdownContent`, \
            which `EchoelStudioView.body` evaluates PERMANENTLY, and that body hosts every \
            `.menu` Picker of the instrument — so this read makes the ROOT an observer of the \
            bio publisher and tears an open Picker down on every publish (10.76.41/50). \
            `AnyView(...)` is not an observation boundary. ⛔ THIS MESSAGE USED TO SAY the \
            line "is built from a STATIC mapping precisely so it needs no read" — true until \
            #640, which made the sentence name its driver and therefore needs one. The law did \
            not move: the read went into `BodyShapesThisSoundLine`'s own body, so the host \
            still observes nothing. Live VALUES remain `AlwaysOnBioPanelStrip`'s job.
            """)
    }

    // MARK: - source access

    private struct BodyRowAnchorMissing: Error { let reason: String }

    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BodyRowAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    /// Brace-matched body of `soundPanel` (#408). A fixed line window is unsound in this file,
    /// where a single member carries forty-line comment blocks and `SourceText.codeOnly`
    /// preserves the line count.
    private func soundPanelBody() throws -> String {
        let code = try codeText(Self.studio)
        guard let anchor = code.range(of: "private var soundPanel: some View"),
              let open = code.range(of: "{", range: anchor.upperBound..<code.endIndex) else {
            throw BodyRowAnchorMissing(reason: """
                `private var soundPanel: some View` was not found in \(Self.studio) — that is \
                the live timbre editor behind the Sound chip. Re-anchor rather than letting \
                these scans pass on nothing (#454).
                """)
        }
        var depth = 0
        var i = open.lowerBound
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return String(code[open.lowerBound...i]) }
            }
            i = code.index(after: i)
        }
        throw BodyRowAnchorMissing(reason: "`soundPanel`'s braces do not close")
    }
}
