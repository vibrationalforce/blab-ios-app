// TheMetricSheetRowsSayWhoseBodyTests.swift
// Echoel — #637: the metric guide's mapping rows drew the demo generator's numbers at full
// strength and spoke them to VoiceOver with no origin, under a header that said "demo".
//
// WHAT THIS GUARDS. `BioMetricsGuideView` — one sheet off the bio strip
// (`BioStripView.swift`: `.sheet(isPresented: $showGuide)`) — renders the section "How your
// body shapes the sound": four `BioSoundMapping` rows, each a two-decimal live amount, a
// filled accent bar, and its OWN accessibility element ending "Currently 62 percent."
//
// ⚠️ It has TWO doors, not one, and both sit on the strip that already says "Demo":
// `infoButton` (the ⓘ) and `drivingIndicator` (the activity light — "is my body driving this
// right now?"). Both set `showGuide = true`. Naming only the ⓘ would understate how close the
// unmarked rows were to the marker: the light is the FIRST thing the strip answers, and the
// tap on it is the one a player makes while asking exactly this question.
//
// ⛔ WHY THE #627b MARKING WAS NOT ENOUGH, and this is the whole finding. #627b put
// "demo values, not your body" in the SECTION HEADER and stopped there. Below it every row
// still drew `EchoelTheme.accent` for the number, a full-strength accent `liveBar`, and an
// accessibility label with no prefix. Two readers get two different answers from one sheet:
// a sighted user reads the loudest thing on the row, which was unmarked; a VoiceOver user
// rotoring row to row NEVER LANDS ON THE HEADER AT ALL, because `.accessibilityElement
// (children: .combine)` makes each row its own element. Half-marked is worse than unmarked
// — it teaches the reader that an unmarked number is the real one (#636's law).
//
// ⛔ AND THE HEADER'S OWN CONDITION MAKES IT SHARPER, not milder: under Simulation `liveBio`
// is NON-nil, so the "read your pulse to see it move" hint disappears. The sheet did not
// merely omit a footnote; it withdrew the only sign that a body was missing and then printed
// four confident measurements of it.
//
// ⚠️ THE STRUCT NAMED IN THREE OLDER GUARDS WAS THE WRONG ONE, corrected here and in them.
// `BioMetricInfo.swift` holds TWO sheets with two separate doors:
//   · `BioMetricInfoView`  ← `.sheet(item: $explain)`, the per-cell tap. Static explanation
//     text only — it reads no bio at all, so it neither marks nor over-claims.
//   · `BioMetricsGuideView` ← `.sheet(isPresented: $showGuide)`, the ⓘ. This is the one with
//     live values, the #627b header and, since this slice, marked rows.
// `TheDemoSourceIsMarkedWhereItRendersTests` (claim 12, INCLUDING its failure message — the
// worst place for it), `TheAlwaysOnRowsSayWhoseBodyTests` and `TheGlanceSaysWhetherItIsABodyTests`
// each named `BioMetricInfoView` for work that lives in `BioMetricsGuideView`. A guard message
// that names the wrong type sends the next session to a file that is already correct — the
// #472 defect wearing a type name.
//
// KIND (§1): claim 10 is **END-TO-END BEHAVIOUR** — `BioModulationMap`, `BioSoundMapping` and
// `BioSampleFrame` are public Foundation-only value types, so this bundle drives the real
// producer. Claims 1–9 are SOURCE-TEXT SCANS: the rows are `private` members of a SwiftUI
// `View` no test bundle here can instantiate. That the founder SEES the dimming and HEARS the
// prefix is a DEVICE PROBE and stays open. ⛔ The first version wrote "(backlog, with 2528)"
// and there is no 2528 anywhere in this repo — not a board id, not a decisions row, not
// another guard; the number was carried over from a device-probe list that does not use it.
// A pointer the next session cannot resolve is worse than none, so it is removed rather than
// repaired to a guess.
//
// GRADING (#433 / §3), transcribed in Python against the parent (54e4612) and the worktree,
// code-only and whitespace-collapsed, EVERY assertion driven — not only the changed ones (§3's
// blind-spot rule):
//   · This file DOES compile against the parent: it names no new Swift symbol, only new text.
//     So every claim has a real verdict there, and none is excused as "not gradable".
//   · **10 REGRESSIONS** — 1a, 1b, 1c, 2a, 3, 4, 5a, 5c, 6a, 6b. Nine go 0 → 1; 2a is the
//     odd one and the strongest, an ABSENCE that is 1 on the parent (`liveBio.flatMap` is the
//     parent's own line) and 0 here. They are ten distinct rendered facts but ONE finding:
//     the row carried no provenance and read its frame twice. Counting them as ten defects
//     would be #486 in the flattering direction.
//   · **2 FORWARD guards** — 2b and 5b. Both are absences over text that does not exist on the
//     parent either, so neither could ever have been red there. Booking an absence-over-an-
//     absent-symbol as a regression is the #635b mistake, one slice old.
//   · **5 SOURCE COUNTERWEIGHTS** — 7a, 7b, 8, 9a, 9b, green on both trees and the point of the
//     file: the section keeps its own spelling, no fourth spelling is minted, the missing-body
//     hint survives the marking, and #498's "—" plus the bar's `live` gate are not traded away
//     for it.
//   · **1 END-TO-END COUNTERWEIGHT** — claim 10, green on both trees by construction.
//   · Arithmetic, so it can be re-derived rather than trusted: 10 test methods, 20 assertion
//     STATEMENTS, of which 17 are source-text scans and 3 belong to claim 10. Claim 10's two
//     in-loop assertions execute four times each; that is 4 iterations of 2 statements, not 8
//     assertions — counting executions would be #486's flattering direction wearing arithmetic.
//
// Stripper: delegates to `SourceText.codeOnly` (#453), and here it is **TRAGEND — 2 of the 17
// text assertions flip raw vs stripped**, measured needle by needle and not inferred from the
// shape of the diff (#623/#625). Both are in claim 7, and they flip for one reason: this
// slice's own ⚠️ comment in `BioMetricInfo.swift` enumerates the three established spellings.
// Raw, `"demo values, not your body"` counts 3 (want 1) and `Bio source: simulated demo`
// counts 1 (want ZERO — the absence claim would fail against the very comment that explains
// why the spelling is absent).
//
// ⛔ AND THE TRANSCRIPTION TOOL WAS WRONG BEFORE THE SOURCE WAS. My Python reimplementation of
// `codeOnly` consumed a backslash escape WITHOUT re-emitting it (`i += 2`, no append), so every
// `\(interpolation)` inside a string literal lost two characters and claim 6b read RED against
// correct code. `SourceText.stripLine` appends both. §0 says a guard you have not driven you
// have not graded — the corollary this cost me is that the DRIVER needs grading too, and a
// transcription wrong in the harsh direction is only cheaper than one wrong in the generous
// direction because it argues with you instead of agreeing.
//
// ⚠️ #364: a DIFFERENT marking is not forbidden. A per-row "Demo" chip like `AlwaysOnBioRow`'s,
// or the whole sheet refusing to draw amounts under a synthetic frame, would satisfy the law
// and turn claims 1–6 red. That is the moment to rewrite this file, not to restore the
// ternaries. What is forbidden silently is a `.fallback` frame reaching these rows with nothing
// on the row that says so.
//
// ⚠️ AND THE CHIP IS THE STRONGER OPTION THIS SLICE DID NOT TAKE — registered so the choice is
// on the record rather than implied. For a SIGHTED user the row's marking is COLOUR-ONLY
// (`EchoelTheme.dim` instead of `EchoelTheme.accent`), which is not self-describing: someone
// who never saw the accent version cannot decode it, and `Text(m.target)` stays accent anyway.
// The only TEXTUAL marking a sighted user gets is the section header — which sits inside the
// `ScrollView` above four multi-line rows on a `.medium` detent, so it scrolls off while the
// rows stay visible. That is the same failure this slice fixes for VoiceOver, in the visual
// channel. `AlwaysOnBioRow`'s per-row `Text("Demo")` chip does not have it. Deferred, not
// overlooked: the chip changes the row's layout and the founder has an open device-probe
// backlog on this family already.
//
// ⚠️ Do NOT read the dimming as the faintness this file complains about twice ("was dim = 0.55
// opacity, too faint", at the two prose `Text`s). `EchoelTheme.dim` was lifted to 0.65 and
// clears WCAG AA on `surface`; those two comments describe a state that no longer exists.
//
// ⭐ THE OVER-CLAIM THIS BLOCK REGISTERED AS OPEN IS **CLOSED BY #638**, ticked off here in
// the commit that closed it rather than left to rot for two cycles like the three bullets
// below it had. It read: `BioSoundMapping.all`'s HRV row says "more variability opens the
// reverb", the mapping CLAUDE.md struck at #546, rendered to a user and guarded by nothing.
// #638 rewrote it — and found the register itself had been too NARROW: the same four-row
// table was also selling a heart-rate filter sweep deleted at #331 and a breath filter
// modulation whose channel (`breathDepth`) has no producer. Three false rows, not one.
// Guards: `Tests/CISmoke/DisabledReverbIsNotClaimedLiveTests.swift` (the reverb decision,
// which owns it, #416) and `Tests/CISmoke/TheGuideTableMatchesTheAuditedWritesTests.swift`
// (the whole table against `AlwaysOnBioChannel.shapedParameters`, end-to-end).
//
// ⚠️ AND #638 PUT A FOURTH FALSE ROW IN BEFORE TAKING IT OUT AGAIN — worth recording next to
// the finding it came from. Its first draft rewrote HRV as "opens the filter a little
// further"; HRV never touches `filterCutoff`, which is a function of coherence alone in both
// branches. A slice correcting a false mapping wrote a new one in the same commit, and the
// audited table two directories away already said `case .hrv: return [.brightness]`. That is
// why the new guard compares the two tables instead of adding a fifth careful comment.
//
// ⚠️ STILL OPEN in the provenance family after this slice — corrected twice since, so read the
// ticks rather than the original list: ⭐ `soundPanelSentence` is CLOSED (#640, together with
// `AutomationStatus.emptySentence`, which this list never named and which says "right now");
// ⭐ OSC is CLOSED (#639). ⭐ `bioPanelSentence` and `alwaysOnSentence` — the two that said
// "four body channels" — are CLOSED (#643): one conditional subject each, the flag taken from
// the same raw frame their own rows use, and the Bio panel's copy moved into
// `AlwaysOnBioPanelStrip` so that flag never has to be read in a root body.
// ⛔ **AND #643's REVIEW FOUND SIX ENTRIES THIS REGISTER NEVER HELD** — measured, each with a
// mount, not guessed. They are listed here because a register short by an entry is the failure
// mode this whole file exists to document, and it has now happened four times:
//   · ⭐ **CLOSED (#644)** — `Text("What your body is doing to the sound")` and its
//     `.accessibilityHint`. The literal no longer lives in `EchoelStudioView`: the whole
//     disclosure moved to `LiveNarrationDisclosure.swift` and the three strings to
//     `BioNarrationDriver.heading`. ⛔ TWO CLAIMS IN THIS ENTRY WERE WRONG WHEN WRITTEN: it
//     "renders while RUNNING" — the surface is UNMOUNTED and has been since a founder decision
//     on 2026-07-12 — and it is the LEAST-read of the three, not the most (measured mounts: 1,
//     1, 0). ⛔ AND THE FIX'S OWN FIRST CUT WAS HALF: a `Bool` collapsed "a real body" and
//     "nothing measured" into one heading, so it still said "your body" over "no pulse measured
//     yet" — the case THIS REGISTER had already written down four bullets below. A register
//     entry that predicts the next slice's defect only helps if the next slice reads it.
//   · `EchoelStudioView.swift` `"Ideas from your pulse — tap to keep. Your body wants …"` — the
//     density traces `bus.usableBio()`, so under the demo this attributes a PREFERENCE to the
//     reader that no body expressed. The strongest possessive claim anywhere in this family.
//     Its sibling ("your body curates, you pick") is capability copy — triage low, not zero.
//   · `BioMetricInfo.swift` `Text("What your body is showing")` — the TOP heading of the very
//     sheet #637 marked. A second header 54 lines down IS qualified. One sheet, one marked
//     header and one unmarked, which is worse than neither.
//   · `EchoelStudioView.swift` `.accessibilityHint("Sounds a held tone whose colour follows your
//     body")` — sibling of a caption this register DOES name, but a distinct string. The
//     #632/#627b pattern exactly: the register held the visible half and not the spoken one.
// ⛔ **AND TWO SENTENCES ABOUT THE SAME MECHANISM NOW TAKE DIFFERENT FRESHNESS GATES.** The Bio
// panel's reads `bus.latestBio` RAW (#643); the Sound panel's `BodyShapesThisSoundLine` reads
// `bus.usableBio()` (#640). Both describe the ALWAYS-ON timbre path, which polls raw — so the
// raw one is right and #640's is the one to move. Not moved here: the Sound panel's other
// sentence (`AutomationStatus.emptySentence`) shares that gate, and `TheSoundPanelNames
// ItsActualDriverTests` claim 8 pins the spelling for same-screen consistency. Changing one
// without the other trades a cross-screen disagreement for a same-screen one. Own slice.
// ⚠️ AND A NIL FRAME RENDERS THE BODY BRANCH: `frame?.source.isSynthetic == true` collapses
// "nothing is arriving" into "a real body". The ROW answers "—" in that state on purpose; the
// sentence prints a positive claim. It survives only because the sentence says "while a session
// runs", which is weaker than the doc's own premise that this is a present-tense claim. A third
// wording is the fix and it is a decision, not a typo.
// Still open, from the original list: the two
// `EchoelStudioView` captions, `BodyTempoField`'s unconditional
// "Tempo, driven by your body", and ADM-OSC / Art-Net / sACN / the discrete events (#462,
// second half). ⭐ The THREE `EchoelFXView` strings that no register held until #640's review
// went looking are triaged and closed as an entry by #641 — and the Live half RE-OPENED and
// RE-CLOSED by #642: both section headers are marked (they render WHILE their rows are live, and
// the rows already said "Demo"), and the two instructional strings are deliberately left alone
// because they render precisely when nothing is being claimed about a current reading.
// ⛔ #641 CLOSED THE LIVE HEADER OVER A LIVE OVER-CLAIM. A section of only LFO routes still said
// "body → sound" over an oscillator; its own review registered that and left it. #642 moved the
// heading's four states into `LiveModOrigin` (`Core/FXModulation.swift`), so one of these THREE
// `EchoelFXView` strings no longer lives in `EchoelFXView` at all. Ticked here, in the commit
// that moved it — this register's own lesson is that a per-entry list only beats a count if the
// entries get ticked off in the commit that closes them, and #642's first cut updated the
// sibling register and not this one. See `TheFXHeadersSayWhoseBodyTests`. ⛔ They were invisible because the sibling register's
// correction OVERSHOT: having found one wrong symbol in that file it declared the whole FILE
// clean ("grep the FILE and you find one 'body'" — measured: 48 lines, seven `var body`).
// Retracting a wrong entry is cheap; closing a file nobody re-opens is not.
// ⛔ `EchoelFXView.stopsArrivingNote` STOOD IN THIS LIST AND DOES NOT BELONG:
// its STRING reads "When a channel stops arriving, its routes here release…" and contains the
// word "body" nowhere (the file does — `var body: some View` — which is exactly how a careless
// grep would have "confirmed" the entry). It was carried into three registers as one of "the four body sentences"
// without anyone grepping it — the count was right about four ITEMS and wrong about which,
// and the item it displaced (`emptySentence`) is the strongest present-tense claim of the
// set. `BioModContributionRow` is CLOSED (#635b) and `BioMetricsGuideView` is closed here —
// both were listed as open in THREE guards, and all three are ticked off in this commit
// (`TheAlwaysOnRowsSayWhoseBodyTests`, `TheGlanceSaysWhetherItIsABodyTests`,
// `TheDemoSourceIsMarkedWhereItRendersTests`). ⛔ The first version of this line said "the two
// guards named above" and claimed the `BioModContributionRow` half was already corrected —
// it was not; #635b landed two cycles ago and all three bullets still read "Next slice" /
// "STILL OPEN" / "unmeasured". A register only beats a count if entries get ticked off in the
// commit that closes them, which is a rule one of those three files already carries verbatim.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMetricSheetRowsSayWhoseBodyTests: XCTestCase {

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static let sheet = "Sources/Echoelmusic/Studio/BioMetricInfo.swift"

    /// Comments blanked (`SourceText.codeOnly`, #453) and then whitespace COLLAPSED.
    ///
    /// ⚠️ The collapse is not cosmetic and not a line-window in disguise. Two of the
    /// expressions this file pins are wrapped across lines by the 100-column style
    /// (`.foregroundStyle(amount == nil || synthetic ? … )` and the VoiceOver label), so a
    /// line-based `contains` would be red on correct code the first time someone reflows a
    /// ternary — #364 by formatting. Collapsing makes the needle describe the EXPRESSION and
    /// not its typography.
    private func collapsedCode(_ relative: String) throws -> String {
        let path = sourceRoot().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        let code = SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
        return code.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func collapsed(_ needle: String) -> String {
        needle.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func count(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: collapsed(needle)).count - 1
    }

    // MARK: - 1–2  the row reads ONE frame, and derives both answers from it

    /// 1 — REGRESSION, and the claim BOTH reviewers of this slice had to put here. `liveBio` is
    /// `bus.usableBio()`, and that call re-reads the wall clock on EVERY evaluation. `latestBio`
    /// cannot change mid-body (all `@MainActor`, body evaluation is synchronous), but TIME can
    /// cross the frame's freshness window between two calls. #637's first version read `liveBio`
    /// once for the amount and once for the origin, in that order, so at the boundary the row
    /// could print a non-nil demo value with `synthetic == false` — a demo number at full
    /// strength, spoken as measured, which is the exact defect this slice removes.
    ///
    /// ⚠️ The fix is a BINDING, so this claim pins all three lines: the bind, and both
    /// derivations reading `frame`. Pinning only the bind would stay green on a tree that kept
    /// `let frame` and went on reading `liveBio` below it (#343 — the counterweights are the
    /// content, and here the "counterweight" is the other half of the same statement).
    func testTheRowBindsOneFrameAndDerivesBothAnswersFromIt() throws {
        let code = try collapsedCode(Self.sheet)
        XCTAssertEqual(count("let frame = liveBio", in: code), 1, """
            The mapping row no longer binds the frame once. `liveBio` is `bus.usableBio()`, \
            which re-reads the wall clock per call, so two reads can straddle the freshness \
            window and disagree about the same row.
            """)
        XCTAssertEqual(
            count("let amount = frame.flatMap { BioModulationMap.measuredAmount(forMappingID: m.id, in: $0) }",
                  in: code), 1, """
            The amount is no longer derived from the bound `frame`.
            """)
        XCTAssertEqual(count("let synthetic = frame?.source == .fallback", in: code), 1, """
            The origin is no longer derived from the bound `frame`. Both answers must come \
            from ONE evaluation or the row can mark itself and its own number differently.
            """)
    }

    /// 2 — REGRESSION (first needle) and FORWARD (second). The other half of claim 1, written
    /// as an ABSENCE so that any correct restructuring passes: whatever the row is called, it
    /// must not reach for `liveBio` a second time. `liveBio.flatMap` is the parent's own line
    /// and is 1 there, so this is a genuine regression, not a needle over a symbol that never
    /// existed.
    ///
    /// ⚠️ Deliberately NOT a count pin on `liveBio` file-wide. The SECTION HEADER legitimately
    /// evaluates it twice (`liveBio == nil`, `liveBio?.source == .fallback`) and a designer may
    /// reasonably change that; pinning the total would turn an ordinary header edit red, which
    /// is #364 exactly. What is pinned is the ROW's own shape.
    func testTheRowDoesNotReachForTheFrameASecondTime() throws {
        let code = try collapsedCode(Self.sheet)
        XCTAssertEqual(count("liveBio.flatMap", in: code), 0, """
            The amount is computed from a fresh `liveBio` call again. That is the second \
            evaluation claim 1 exists to remove — it re-reads the wall clock and can disagree \
            with the origin read beside it.
            """)
        XCTAssertEqual(count("let synthetic = liveBio", in: code), 0, """
            The origin is computed from a fresh `liveBio` call. Same straddle, other side.
            """)
    }

    // MARK: - 3–5  what the eye reads

    /// 3 — REGRESSION. The number is the row's headline and it was the unmarked part.
    /// `amount == nil` (never measured) and `synthetic` (measured, but not by a body) both
    /// dim it — deliberately the same treatment, because both mean "do not read this as your
    /// body", and the row keeps its "—" for the first case to tell them apart.
    func testTheNumberDimsForADemoFrame() throws {
        let code = try collapsedCode(Self.sheet)
        XCTAssertEqual(
            count(".foregroundStyle(amount == nil || synthetic ? EchoelTheme.dim : EchoelTheme.accent)",
                  in: code), 1, """
            The mapping row's value is no longer dimmed for a synthetic frame. A \
            full-strength `EchoelTheme.accent` number under a header that says \
            "demo values, not your body" is the half-marking this slice removed.
            """)
    }

    /// 4 — REGRESSION. The bar is LOUDER than the number — a filled accent capsule is the
    /// first thing the eye lands on. A dimmed number beside a full-strength bar would be a
    /// footnote contradicting its own headline.
    func testTheLiveBarDimsForADemoFrame() throws {
        let code = try collapsedCode(Self.sheet)
        XCTAssertEqual(
            count(".fill(synthetic ? EchoelTheme.dim : EchoelTheme.accent)", in: code), 1, """
            `liveBar` fills a demo value in full `EchoelTheme.accent` again. The bar is the \
            loudest element on the row; marking the number alone leaves the over-claim in place.
            """)
    }

    /// 5 — REGRESSION (a, c) and FORWARD (b). `synthetic` is REQUIRED on `liveBar`, per
    /// #431/#440/#443: a defaulted argument no call site writes appears in NO diff, and this
    /// is exactly the parameter a future second call site would forget. There is one call
    /// site, so requiring it costs one edit and buys the compiler as the reviewer.
    func testTheBarsProvenanceArgumentIsRequiredAndWritten() throws {
        let code = try collapsedCode(Self.sheet)
        XCTAssertEqual(
            count("private func liveBar(_ amount: Float, live: Bool, synthetic: Bool) -> some View",
                  in: code), 1, """
            `liveBar` no longer takes the row's provenance. Its fill colour cannot then \
            depend on it.
            """)
        XCTAssertEqual(count("synthetic: Bool =", in: code), 0, """
            `synthetic` acquired a DEFAULT. A defaulted argument that no call site writes \
            never shows up in a diff (#431/#440/#443) — which is how a second call site ships \
            drawing a demo value at full strength with nothing to review.
            """)
        XCTAssertEqual(
            count("liveBar(amount ?? 0, live: amount != nil, synthetic: synthetic)", in: code), 1, """
            The one call site no longer passes the row's own `synthetic`. A required argument \
            filled with a literal would compile and mark nothing.
            """)
    }

    // MARK: - 6–7  what VoiceOver hears, and in which of the three established spellings

    /// 6 — REGRESSION, and the sharpest half of the finding: each row is its own
    /// accessibility element, so the header this sheet already had is unreachable by rotor.
    /// The label is a sentence that CONTINUES ("Heart rate shapes …"), so it takes the PREFIX
    /// form — the second of the three spellings, chosen by position and not by taste.
    ///
    /// ⚠️ THE NEEDLE IS POSITION-AGNOSTIC ON PURPOSE (#364). Its first version pinned the
    /// INLINE form `(synthetic ? "Simulated demo, " : "")`, which would have gone red on the
    /// hoisted `let origin = synthetic ? …` idiom that three of the four sibling surfaces
    /// already use (`HeaderMonitors`, `EchoelFXView`, `AlwaysOnBioRow`) — and the hoist is also
    /// the mitigation for #287's "unable to type-check this expression in reasonable time",
    /// which this bundle has been red for before. A guard that forbids the house idiom AND the
    /// compile-risk mitigation in one needle is a guard that gets deleted.
    ///
    /// The second assertion is what the first gives up: it keeps the origin FIRST in the
    /// sentence, which is the whole point of the prefix form.
    func testVoiceOverHearsTheOriginBeforeTheSentence() throws {
        let code = try collapsedCode(Self.sheet)
        XCTAssertEqual(count("? \"Simulated demo, \" : \"\"", in: code), 1, """
            The row's accessibility label no longer carries the origin. Each row is its own \
            element (`.accessibilityElement(children: .combine)`), so a VoiceOver user \
            rotoring through them never reaches the section header — the label is the ONLY \
            place the origin can be heard.
            """)
        XCTAssertEqual(
            count("origin + \"\\(m.source) shapes \\(m.target). \\(m.direction).\" + measured", in: code), 1, """
            The origin is no longer the FIRST thing spoken. A demo marker after "Currently 62 \
            percent" is heard too late to change how the number was read.
            """)
    }

    /// 7 — COUNTERWEIGHTS, and the reason this slice did not "harmonise" anything. Three
    /// spellings are established and they differ by POSITION: `"Bio source: simulated demo,
    /// not your body"` LABELS a whole element · `"Simulated demo, "` PREFIXES a continuing
    /// sentence · `"demo values, not your body"` HEADS a section. After this slice the file
    /// legitimately holds TWO of the three, inside ONE section, and that is correct rather than
    /// inconsistent — they mark different things: a section, and an element inside it. A fourth
    /// spelling of one decision is what #634b had to retract.
    func testTheSectionKeepsItsOwnSpellingAndNoFourthIsMinted() throws {
        let code = try collapsedCode(Self.sheet)
        XCTAssertEqual(count("\"demo values, not your body\"", in: code), 1, """
            The SECTION header's spelling changed or was duplicated. It stays as it is: the \
            header labels a section, the row label prefixes a sentence, and collapsing the two \
            into one string makes one of the two read wrong (#416 is about one DEFINITION per \
            decision, not one string per repo).
            """)
        XCTAssertEqual(count("Bio source: simulated demo", in: code), 0, """
            The element-LABEL spelling appeared in this sheet. That form belongs to a surface \
            whose whole element is the bio source (the strip, the widget, the watch face); \
            here it would be a fourth spelling in a file that already carries two correct ones.
            """)
    }

    // MARK: - 8–9  what the marking must NOT eat

    /// 8 — COUNTERWEIGHT. The `liveBio == nil` branch is a DIFFERENT statement ("no body at
    /// all") and it must survive the demo marking. Under Simulation `liveBio` is non-nil, so
    /// this hint disappearing is precisely what made the unmarked rows an assertion rather
    /// than an omission — the two branches are not interchangeable.
    func testTheMissingBodyHintSurvivesTheMarking() throws {
        let code = try collapsedCode(Self.sheet)
        XCTAssertEqual(count("\"read your pulse to see it move\"", in: code), 1, """
            The "no body at all" hint is gone. It is not the same statement as the demo \
            marker: one says nothing is arriving, the other says something is arriving and it \
            is not you.
            """)
    }

    /// 9 — COUNTERWEIGHT (#498/#500). `measuredAmount` returns nil where the field was never
    /// measured, and the row prints "—" and draws only the muted track. Marking the demo must
    /// not be paid for by collapsing that distinction into a confident "0.00".
    func testTheUnmeasuredAffordanceSurvivesTheMarking() throws {
        let code = try collapsedCode(Self.sheet)
        XCTAssertEqual(count("?? \"—\"", in: code), 1, """
            The "—" for an unmeasured field is gone. `measuredAmount` exists precisely so a \
            field the body never produced does not render as a specific number.
            """)
        // ⚠️ ANCHORED ON `liveBar`'s BODY, not on its call site. The first version pinned
        // `live: amount != nil`, which is a strict SUBSTRING of claim 5c's call-site needle —
        // it could not be red while 5c was green, so it was one fact counted twice and it
        // inflated this file's counterweight tally by one. §3 says a grade wrong in the
        // generous direction is the same defect as one wrong in the harsh direction, and an
        // assertion that cannot fail independently is exactly that, in miniature.
        XCTAssertEqual(count("if live { Capsule()", in: code), 1, """
            `liveBar` no longer gates its fill on whether the field was measured, so an \
            unmeasured field draws a zero-width fill instead of NO fill at all — which is what \
            distinguishes "never measured" from "measured, demo" once both dim.
            """)
    }

    // MARK: - 10  END-TO-END: why the origin field was unavoidable

    /// 10 — COUNTERWEIGHT, and the one claim in this file that drives shipped code rather
    /// than reading it. It proves the marking could NOT have been derived from what the row
    /// already had: neither `BioModulationMap.amount` nor `isMeasured` reads `frame.source`,
    /// so a demo frame and a camera frame carrying the same numbers produce byte-identical
    /// rows. Every mapping reports MEASURED for a frame with all four fields populated, so
    /// "it would have shown — anyway" is false and the `frame?.source` read is the only thing
    /// that can tell a demo from a body. ⚠️ The frame here is hand-built, NOT taken from
    /// `BioSimulator`; see the failure message for exactly what that does and does not prove.
    func testADemoFrameIsIndistinguishableFromABodyByAmountAlone() {
        func frame(_ source: BioSource) -> BioSampleFrame {
            BioSampleFrame(timestamp: 1000, heartRateBPM: 64, hrvNormalized: 0.45,
                           breathRate: 12, breathPhase: 0.3, coherence: 0.62,
                           motionEnergy: 0, source: source)
        }
        let demo = frame(.fallback)
        let body = frame(.cameraPPG)

        XCTAssertEqual(BioSoundMapping.all.count, 4,
                       "the guide's mapping list changed size; re-read this claim against it")

        for m in BioSoundMapping.all {
            let d = BioModulationMap.measuredAmount(forMappingID: m.id, in: demo)
            let b = BioModulationMap.measuredAmount(forMappingID: m.id, in: body)
            XCTAssertNotNil(d, """
                "\(m.id)" reads UNMEASURED for the frame built above. ⚠️ READ THE NAME: what \
                this proves is that a frame with all four fields populated reports measured — \
                it does NOT drive `BioSimulator`, and nothing in this test binds the two. That \
                the demo generator actually produces such a frame is true today \
                (`Bio/BioSimulator.swift` clamps HR 58…92, HRV and coherence 0.2…0.9 and \
                hardcodes breathRate 12, all inside the measured gates) and is stated as a \
                fact I checked, not as something this assertion enforces. If someone makes the \
                simulator emit coherence 0, this stays green and that sentence becomes false \
                — which is why it is written down here rather than left implied (#367).
                """)
            XCTAssertEqual(d, b, """
                "\(m.id)" now yields a different amount for `.fallback` than for `.cameraPPG` \
                on identical numbers. Something started reading `frame.source` inside \
                `BioModulationMap`; that is a second definition of this decision (#416) and \
                the row's marking should be re-derived from it rather than left in two places.
                """)
        }
    }
}
