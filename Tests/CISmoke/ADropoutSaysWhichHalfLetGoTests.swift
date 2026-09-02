// ADropoutSaysWhichHalfLetGoTests.swift
// Echoel — #540. Two freshness regimes, one screen, and only one of them said so.
//
// WHAT THIS IS ABOUT. `EchoelFXView` shows the body moving the sound in two stacked sections:
// the FX routes the player configured, then the four always-on channels that shape the
// instrument's own timbre. When a source stops arriving — a finger lifts off the camera, a
// strap drops — those two sections behave DIFFERENTLY, on purpose:
//   · the routes are gated on `usableBio()`, so they release and the row falls to a dash;
//   · the timbre producers read `bus.latestBio` raw and dedupe, so they PARK on the last
//     reading and the row says "held".
// #499 established that both regimes are correct and corrected the false comment that claimed
// they were one. `TwoFreshnessRegimesAreDeliberateTests` pins the CODE halves. What it left —
// in its own words, "the visible residue is real and is not fixed here … only the timbre half
// says so on screen" — is the PLAYER's half: two different words appear during one dropout and
// nothing tells them that is deliberate rather than a fault. #540 adds the sentence pair; this
// guard keeps it true.
//
// ⚠️ THE LIMIT FIRST. Every assertion here is a SOURCE-TEXT SCAN. `BioModLiveView`,
// `AlwaysOnBioRow` (its own file since #553) and `BioModContributionRow` (still `private` in
// `EchoelFXView`) are SwiftUI `View` structs this
// bundle cannot instantiate. So this proves the words exist, say both halves, and are mounted
// under the right section — never that they RENDER, that they fit the sheet at accessibility
// text sizes, that VoiceOver reads the two paragraphs in order, or that the dropout itself
// looks the way the sentence describes. Those four are device checks and all four are OPEN.
//
// ⚠️ HONEST GRADING against the parent tree — TRANSCRIBED (a Python rebuild of every scan below,
// driven against `git show HEAD:` and the worktree), not assumed. Of the EIGHT test methods:
//   · ZERO REGRESSIONS. Nothing here was red on the parent for the reason its name gives.
//   · ONE FINDING, reported FOUR times (#486). `stopsArrivingNote` does not exist on the parent,
//     so `testTheDropoutNoteExists`, `testTheNoteNamesBothHalves`, `testTheNoteIsMountedInThe
//     Footer` and `testTheNewNoteDoesNotClaimThePinnedChannels` all go red together — three by
//     `literalValue` throwing on a zero-hit anchor, one by the body scan finding no mount. That
//     is a single absence, and banking it as four regressions would be the flattering direction
//     of #433. This file is therefore a FORWARD guard over copy this same commit writes.
//   · FOUR are COUNTERWEIGHTS, green on both trees, and they are the content (#343). A file that
//     asserted only "the new sentence exists" would stay green on a tree that deleted the word
//     it promises, stopped drawing the mark it names, swapped the two sections so "below" points
//     the wrong way, or folded the new sentence into the #496-pinned one.
//
// ⛔ AND THE FIRST VERSION OF THIS PARAGRAPH CLAIMED `SourceText.codeOnly` WAS LOAD-BEARING —
// "TWO verdicts flip … the doc comment above `stopsArrivingNote` explains the split in the same
// words the negative scans forbid". MEASURED: **0 of 16** raw-vs-stripped verdicts flip. It is
// PROPHYLAKTISCH, and the reason is structural rather than lucky: `literalValue` starts AT the
// anchor line and walks FORWARD, so a doc comment sitting above it is never in range, and every
// other needle is an exact code expression inside a brace-matched body. The stripper stays,
// because a future edit that moves a comment BETWEEN the anchor and its continuation lines would
// make it matter — but the claim is retracted rather than left standing. #453 asks for the count
// precisely because three slices in a row asserted this without measuring; writing the sentence
// and then measuring it is how this one nearly became the fourth.
//
// ⛔ THIS SLICE SHIPPED UNDER THE WRONG NUMBER. The commit that created this file is titled
// "#504", and #504 already belonged to the `BodyTempoField` defaulted-argument work — it is
// spelled in `Sources/Echoelmusic/Studio/BodyTempoField.swift` and four times in
// `TheTempoFieldAsksWhichVariantTests`. A slice number is a cross-reference handle and nothing
// else; two slices sharing one makes every later "#504" ambiguous in both directions, and the
// commit message cannot be amended because it is pushed. The source and this guard are
// renumbered to #540 in the follow-up; the note stays so a reader who arrives from the git log
// is not left believing the tempo-field slice wrote a bio footer. Found by
// `git grep -c "#504" -- Sources Tests` — the check costs one command and was skipped.
//
// ⚠️ WHAT THIS DELIBERATELY DOES NOT RESTATE (#416). That the FX driver still calls
// `usableBio()` and the two timbre producers still read `bus.latestBio` raw is owned by
// `TwoFreshnessRegimesAreDeliberateTests`. Copying those needles here would be two spellings of
// one decision. This file guards only what that one does not: the words on the screen.

import XCTest
@testable import Echoelmusic

final class ADropoutSaysWhichHalfLetGoTests: XCTestCase {

    private static let fxView = "Sources/Echoelmusic/Studio/EchoelFXView.swift"
    /// #643: the always-on sentence's literal lives here (moved by #542); the FX member of the
    /// same name is now a forwarder with no literal in it.
    private static let channels = "Sources/Echoelmusic/Studio/AlwaysOnBioChannel.swift"
    /// ⛔ THE ROW MOVED (#553). `AlwaysOnBioRow` was a `private` struct in `fxView`; it is now an
    /// internal type in its own file so the Bio panel can mount the same row the FX sheet does.
    /// This anchor is updated in the SAME commit as the move — the failure mode #456 warns about
    /// is not a red gate but a scan that stays GREEN while searching a file the subject left, and
    /// `declarationBody(of:in:)` throwing on absence is the only reason this one could not do that.
    private static let rowFile = "Sources/Echoelmusic/Studio/AlwaysOnBioRow.swift"

    /// Channels this note may not name — and they are banned for TWO different reasons, which
    /// #980 had to split apart.
    ///
    /// ⛔ #980 — THE ONE REASON THIS LIST GAVE WAS FALSE FOR ONE OF ITS FOUR ENTRIES. It read
    /// "the three channels no producer drives — both `…BioParams(` sites pin them to neutral
    /// literals". True of `breath depth` and `LF/HF`; FALSE of `coherence trend` since #813,
    /// which added `Core/CoherenceTrend` and made both sites pass `coherenceTrend: trend`
    /// instead of the literal 0. The consumer is reachable too — the spectral morph in
    /// `EchoelDDSP.applyBioReactive` reads it behind nothing but its own 0.10 deadband.
    /// So this was #367 (it could only fail for a reason that is not true) and #364 (it would
    /// have argued a later session out of correct work), and its own failure message carried
    /// the instruction nobody followed: *"If you gave it a real producer, update this list."*
    ///
    /// ⭐ IT WAS ALSO THE SIXTH HOME, FOUND BY THE REVIEWER AFTER #979 CLAIMED FIVE. #979's own
    /// commit message named the #766/#456 pattern — when every home you checked is the same
    /// KIND, the ENUMERATION is what is incomplete — and then stopped one short of a home that
    /// is the same kind, on the same surface, in the same bundle. The map that would have found
    /// it was already written: `WebsitePagesAreFindableAndHonestTests` names all three Swift
    /// copy guards by file, and this is the middle one.
    ///
    /// ⚠️ The trend STAYS banned here, for the reason `EchoelFXView`'s always-on note gives:
    /// it has no READING to render — `CoherenceTrend` is a `private var` inside each voice, not
    /// a field on `BioSampleFrame`, so no surface can read it. That is STRUCTURAL, and this
    /// note is about what a dropout releases or holds, which needs a reading by definition.
    private static let producerlessChannels = ["breath depth", "LF/HF", "LF-HF"]
    /// Banned for a different reason: real producer since #813, no readable value on any
    /// surface. See the ⛔ note above.
    private static let unreadableChannels = ["coherence trend"]

    // MARK: - the copy (ONE absence on the parent, reported four times — see the header)

    func testTheDropoutNoteExists() throws {
        let note = try literalValue(of: "static let stopsArrivingNote =", in: Self.fxView)
        XCTAssertFalse(note.isEmpty, """
            `BioModLiveView.stopsArrivingNote` is missing or empty. It is the only place a \
            player is told that a dropout releases the FX routes and parks the timbre — \
            without it the screen shows two different words for one event and explains neither.
            """)
    }

    /// Both halves in one string, because the whole point is that the two behaviours are read
    /// TOGETHER. A sentence naming only the release would leave "held" unexplained, which is
    /// the state this slice exists to end.
    func testTheNoteNamesBothHalves() throws {
        let note = try literalValue(of: "static let stopsArrivingNote =", in: Self.fxView)
        XCTAssertTrue(note.contains("release"), """
            the dropout note does not say the routes RELEASE. That is the half a player sees as \
            a dash in the rows directly above it.
            """)
        XCTAssertTrue(note.contains("dash"), """
            the dropout note does not mention the DASH. "—" is what `BioModContributionRow` \
            actually draws for an unmeasured carrier, and naming the mark is what connects the \
            sentence to the thing on screen.
            """)
        XCTAssertTrue(note.contains("held"), """
            the dropout note does not mention "held". That word is rendered verbatim by \
            `AlwaysOnBioRow`, and a player who sees it with no explanation reads a fault.
            """)
    }

    /// A constant nobody renders is prose (the #496 rule, applied to its own successor).
    func testTheNoteIsMountedInTheFooter() throws {
        let body = try declarationBody(of: "private struct BioModLiveView: View", in: Self.fxView)
        XCTAssertTrue(body.contains("Text(Self.stopsArrivingNote)"), """
            `stopsArrivingNote` is declared but never rendered. The always-on note has the same \
            requirement for the same reason: an unmounted string states a truth nobody can read.
            """)
    }

    // MARK: - counterweights (green on both trees — the premises the sentence stands on)

    /// THE ONE THAT CATCHES THE SILENT BREAK. The sentence says the timbre channels are
    /// "below". That is a layout claim: `AlwaysOnBioView()` is mounted directly after
    /// `BioModLiveView(modulator:)`. Swapping those two lines is a one-line edit that makes the
    /// copy point the wrong way with no compiler error, no crash and nothing else to notice.
    func testTheTimbreSectionIsStillBelowTheRouteSection() throws {
        let text = try source(Self.fxView)
        guard let live = text.range(of: "BioModLiveView(modulator:"),
              let always = text.range(of: "AlwaysOnBioView()") else {
            return XCTFail("""
                one of the two live sections is no longer mounted in `EchoelFXView` under the \
                name this scan anchors on. Re-anchor — do not delete: the dropout note says \
                "below", and that word is only true while both sections exist in this order.
                """)
        }
        XCTAssertLessThan(live.lowerBound, always.lowerBound, """
            `AlwaysOnBioView()` is now mounted BEFORE `BioModLiveView(modulator:)`, so the \
            dropout note's "the timbre channels below" points at the routes. Either restore the \
            order or rewrite the sentence in the same commit.
            """)
    }

    /// The word the sentence promises must still be the word the row draws.
    func testTheHeldWordIsStillRendered() throws {
        let body = try declarationBody(of: "struct AlwaysOnBioRow: View", in: Self.rowFile)
        XCTAssertTrue(body.contains("Text(\"held\")"), """
            `AlwaysOnBioRow` no longer renders the literal "held", but the dropout note still \
            tells the player to look for it. Change the word and the sentence together.
            """)
    }

    /// And the mark it promises must still be the mark the other row draws. `"—"` here is
    /// U+2014, the same character the row prints; a swap to a hyphen would make "dash" true in
    /// spirit and this scan red, which is the correct outcome — the sentence would then be
    /// describing a mark the row stopped using.
    func testTheDashIsStillWhatAnUnmeasuredRouteDraws() throws {
        let body = try declarationBody(of: "private struct BioModContributionRow: View",
                                       in: Self.fxView)
        XCTAssertTrue(body.contains(": \"—\""), """
            `BioModContributionRow` no longer falls back to "—" for an unmeasured carrier. The \
            dropout note tells the player a released route "shows a dash"; if the row now prints \
            something else — or worse, a confident 0.00 — both this scan and the honesty rule \
            behind it are broken.
            """)
    }

    /// THE #496 STRING STAYS ITS OWN STRING. The obvious later tidy is to join the two
    /// paragraphs into one constant. That would put the dropout wording inside the sentence
    /// `TheAlwaysOnBioPathIsNamedTests` binds to the two `…BioParams(` construction sites —
    /// making a copy edit about dropouts able to fail a guard about channel inventory, and
    /// vice versa. Two decisions, two strings (#416 read forwards, not backwards).
    func testTheAlwaysOnNoteStaysTheAlwaysOnNote() throws {
        // ⛔ RE-ANCHORED TWICE OVER BY #643, and reading the OLD anchor would have been
        // vacuous rather than red. It was `static let alwaysOnNote =` in `EchoelFXView` — but
        // that member became `static func alwaysOnNote(synthetic:)`, a one-line FORWARDER whose
        // body holds no string literal at all. Anchored there, this scan would have extracted
        // the empty string and every `XCTAssertFalse(note.contains(…))` below would have passed
        // over nothing (#454). The literal lives in `AlwaysOnBioChannel`, where #542 put it.
        // ⛔ RE-ANCHORED A THIRD TIME (#649), AND THIS ONE WAS A LIVE RED ON CORRECT WORK.
        // `literalValue` walks FORWARD from the anchor line and stops at the first line that is
        // not a continuation (`"` `+` `?` `:`). #649 restructured `alwaysOnSentence` from one
        // implicit-return concatenation into `let opening = …` + `return …`, so the line after
        // the anchor now trims to `let opening = synthetic` — the walk broke immediately and
        // extracted "". Two failures, and the SECOND is the one §4 calls worse: `isEmpty` went
        // red, AND the three `contains` assertions below went VACUOUSLY GREEN, so the guard
        // could no longer catch the merge it exists to catch.
        // ⭐ The extractor's own doc predicted this shape ("a blank line inserted mid-declaration
        // WOULD truncate the value") and the ⛔ block above records one earlier re-anchor for a
        // near-identical reason. The fix is NOT to add `let`/`return` to `continuationPrefixes`
        // — that is the fixed-window family #408 deprecates, and it would over-read on the next
        // shape nobody predicted. It is to use the BRACE-MATCHED extractor this same file
        // already declares for exactly this reason.
        let note = try literalsInDeclarationBody(of: "static func alwaysOnSentence",
                                                in: Self.channels)
        XCTAssertFalse(note.isEmpty, "the always-on note vanished — see #496")
        for word in ["held", "release", "dash"] {
            XCTAssertFalse(note.contains(word), """
                the always-on note now contains "\(word)", i.e. the two footer paragraphs have \
                been merged. Keep them separate: one names which channels shape the timbre, the \
                other says what a dropout does to each half, and they are guarded by different \
                files for different reasons.
                """)
        }
    }

    /// The same over-claim trap #496 closed, on the sentence added next to it. A "completeness"
    /// edit reaching for CLAUDE.md's DDSP table would put channels on the product's central
    /// surface that this note cannot honestly describe.
    ///
    /// ⛔ #980: this said "that table lists seven mappings and only four have producers". The
    /// second number moved at #813 — the trend has one — and a stale count inside the very
    /// comment that justifies a ban is how the ban outlives its reason. The count is gone rather
    /// than refreshed: it is a date, not a fact (#818), and the two lists below say what matters.
    func testTheNewNoteDoesNotClaimThePinnedChannels() throws {
        let note = try literalValue(of: "static let stopsArrivingNote =", in: Self.fxView)
        for channel in Self.producerlessChannels {
            XCTAssertFalse(note.contains(channel), """
                the dropout note names \(channel), which no producer drives — both \
                `…BioParams(` sites pin it to a neutral literal, so it can neither release nor \
                be held. If you gave it a real producer, update this list, the always-on note \
                and this sentence together.
                """)
        }
        for channel in Self.unreadableChannels {
            XCTAssertFalse(note.contains(channel), """
                the dropout note names \(channel). It HAS a producer (#813) — the ban is not \
                about that. It has no READING on any surface: `CoherenceTrend` is a `private \
                var` inside each voice, never a field on `BioSampleFrame`, so nothing can show \
                whether it released or was held, which is the only thing this note says. \
                Publishing a readable trend is a real slice; naming it here before that is a \
                promise no surface can keep.
                """)
        }
    }

    // MARK: - source access

    private struct DropoutAnchorMissing: Error { let reason: String }

    /// Comment-stripped source (#453), a SKIP when there is no checkout, a FAILURE when the file
    /// moved (#454 — a skip passes CI, so "no tree" may skip and "my anchor was renamed" may not).
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DropoutAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// What counts as a continuation of a multi-line string expression.
    ///
    /// ⛔ IT WAS `"` AND `+` ONLY, AND #643 WOULD HAVE TRUNCATED THE VALUE SILENTLY. The
    /// always-on sentence grew a ternary — its subject now names the demo generator when the
    /// demo generator is driving — so two of its lines begin with `?` and `:`. The walk would
    /// have stopped at the first of them, kept the head, and dropped the TAIL: `note.isEmpty`
    /// still false, so nothing goes red, while every negative assertion below silently stops
    /// covering the half of the sentence it was written for. That is the #454 failure mode in
    /// its quietest form — not a guard that fails, a guard that shrinks.
    ///
    /// ⛔ AND THE FIRST FIX ADDED `(` AND `)` TOO, WHICH BREAKS THE TERMINATOR IN THE OTHER
    /// DIRECTION. This array is shared by all four call sites, and `)` is how a multi-line CALL
    /// ends — so the walk would continue past a declaration that closes on `)` and absorb the
    /// next one's literals. An OVER-read is the worse direction: a truncated read only makes a
    /// positive assertion red, an over-read can make a negative one red on correct code or bury
    /// a real needle. Neither is needed — the two sentences this exists for open with `"` and
    /// continue with `+`, `?`, `:`.
    private static let continuationPrefixes = ["\"", "+", "?", ":"]

    /// The concatenated contents of the `"…"` literals of a multi-line declaration.
    ///
    /// ⚠️ ITS HONEST LIMIT: it walks forward from the anchor line and stops at the first line
    /// that is neither the anchor nor a continuation (see `continuationPrefixes`).
    /// `SourceText.codeOnly` blanks comment lines while PRESERVING line count, so a doc comment
    /// cannot be swept in — but a blank line inserted mid-declaration WOULD truncate the value,
    /// and the scans above would then fail on correct code. That is the intended direction: a
    /// truncated read makes a positive assertion red, never a negative one green.
    private func literalValue(of anchor: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        let hits = text.components(separatedBy: anchor).count - 1
        guard hits == 1 else {
            throw DropoutAnchorMissing(reason: """
                `\(anchor)` occurs \(hits)× in \(relativePath); this scan needs exactly one so it \
                cannot silently read a different constant.
                """)
        }
        var out = ""
        var started = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !started {
                if line.contains(anchor) { started = true } else { continue }
            } else if !Self.continuationPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
                break
            }
            // Every `"…"` on this line, concatenated in order.
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

    /// Every `"…"` inside the BRACE-MATCHED body of `key`, concatenated in order.
    ///
    /// ⚠️ WHY THIS EXISTS BESIDE `literalValue` RATHER THAN REPLACING IT. The other three call
    /// sites read a `static let` whose value is a bare `+` chain with no braces at all —
    /// brace-matching has nothing to match there. This one reads a FUNCTION, where the body is
    /// exactly what braces delimit, so the shape of the statements inside it stops mattering.
    /// A future `if`, `switch` or hoisted local cannot truncate it (#649).
    ///
    /// ⚠️ Uniqueness is checked HERE and not in `declarationBody`, which takes the FIRST match
    /// (#408): a scan that silently reads a different declaration is the failure this whole
    /// file's anchor history is made of.
    private func literalsInDeclarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        let hits = text.components(separatedBy: key).count - 1
        guard hits == 1 else {
            throw DropoutAnchorMissing(reason: """
                `\(key)` occurs \(hits)× in \(relativePath); this scan needs exactly one so it \
                cannot silently read a different declaration.
                """)
        }
        var out = ""
        var inside = false
        for c in try declarationBody(of: key, in: relativePath) {
            if c == "\"" { inside.toggle(); continue }
            if inside { out.append(c) }
        }
        return out
    }

    /// The brace-matched body following `key`. Brace-matched rather than "to the next
    /// declaration": `EchoelFXView.swift` is long, and deriving scope from FILE ORDER is a
    /// mistake this repo has paid for more than once (#408).
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        guard let start = text.range(of: key) else {
            throw DropoutAnchorMissing(reason: """
                \(relativePath) no longer declares `\(key)`. Re-anchor this scan.
                """)
        }
        guard let open = text[start.upperBound...].firstIndex(of: "{") else {
            throw DropoutAnchorMissing(reason: "no opening brace after `\(key)`")
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
            out.append(c)
            i = text.index(after: i)
        }
        throw DropoutAnchorMissing(reason: "unbalanced braces after `\(key)` in \(relativePath)")
    }
}
