// TheBioPanelRowsSayWhoseBodyTests.swift
// Echoel — #648: two `bioPanel` rows each conditioned on ONE axis and not on the source.
//
// WHAT THIS GUARDS. `BreathVoiceRow` and `AutoModeRow` are the two toggles in `bioPanel`.
// ⛔ THIS LINE SAID "behind the Bio chip" (#705). There is no Bio chip in the STANDING strip: `.bio` is absent from
// `EchoelStudioView.studioChips`, and #290 rejected adding one as a "zweite Tuer". The door is
// a TAP on the pulse pill (`PulseMonitorMiniLive` -> chrome door "bio"), long-press second.
// Each already branched — the first on whether breath was measured, the second on whether a
// source was running — so each LOOKED carefully written. Neither branched on WHOSE reading it
// was. Under Simulation `usableBio()` is non-nil, so `AutoModeRow` renders its enabled branch
// and promises to steer the mood "toward your measured coherence, HRV and heart rate", and
// `BreathVoiceRow` promises a tone whose colour follows "your heart and coherence". Both are
// the demo generator's.
//
// ⭐ THE SHAPE IS THE FINDING, and it is why this class survived five slices of the same family:
// **a row that conditions on one thing reads as conditioned on everything.** A reviewer scanning
// for unconditional claims skips a `? :`. Neither of these is unconditional; both are
// conditioned on the wrong axis.
//
// ⚠️ NO NEW READ. Both rows already call `usableBio()` exactly once and already hold the frame;
// the hints simply stop being fixed strings. ⛔ The first draft of this header said the rows went
// "from two calls to one" and cited #646's straddle — measured on the parent, each made exactly
// one call already. There was no straddle here. That correction is kept because carrying a
// previous slice's mechanism into a place it does not fit is the same error the family keeps
// correcting in user-facing copy.
//
// ⚠️ COMPOSED, NOT ENUMERATED. Breath-measured × source is four combinations; heart/coherence ×
// source is two. Six literals is how two of them drift, so only the SUBJECT is shared. Never a
// whole sentence — that collapse is what #634b had to retract.
//
// ⚠️ FOUR FORMS EXIST AND THIS IS ONE OF THEM. `"Bio source: simulated demo, not your body"`
// labels a whole ELEMENT (strip · widget · watch); `"Simulated demo, "` PREFIXES a spoken
// sentence; `"demo values, not your body"` names a section HEAD; `"the simulated demo source,
// not your body"` is the MID-SENTENCE subject this file shares — since #649 owned once, by
// `BioProvenanceCopy.demoSubject`. Claim 5 keeps the other THREE out of these rows.
// ⛔ This said THREE and omitted the section head, while the retraction at the definition and
// this file's own claim 5 both say four and ban three spellings. One census, two numbers, in
// one bundle (reviewer finding, #649).
//
// KIND (§1): **MIXED.** Claims 1–4 DRIVE `BioPanelRowCopy`, a pure enum in the Foundation-only
// `AlwaysOnBioChannel.swift` — END-TO-END, the strong kind. Claims 5–6 are SOURCE-TEXT SCANS:
// both rows are `private` structs inside `EchoelStudioView.swift`. **DEVICE PROBE, open:**
// nobody here can hear VoiceOver speak a hint, and nobody can see the caption reflow.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (1f51ee9). This bundle names
// `BioPanelRowCopy`, so it DOES NOT COMPILE against the parent: **no assertion has a verdict
// there**, and every bullet below is a hand-transcription of what each needle would find (§3 —
// the ambiguity that let #488 ship a red gate for a cycle).
//   · **2 TRUE REGRESSIONS — 5a and 5b.** Both fixed strings genuinely occur in the parent's
//     row bodies, and each claim's named reason is exactly that.
//   · **1 ABSENCE, REPORTED FOUR TIMES — 6a–6d.** `BioPanelRowCopy` does not exist on the
//     parent, so all four needles in claim 6 miss for ONE cause (#486). ⛔ This said "6a and 6b"
//     while the loop carries FOUR needles, in a header whose own rule two bullets up is that a
//     loop iteration is one assertion each. Undercounting an absence is the harsh direction of
//     the same defect — it still means the number was not derived from the file.
//   · **4 FORWARD, BEHAVIOURAL (claims 1–4)** — they drive the four pure statics. Loop
//     iterations are ONE assertion each, not one per execution.
//   · ⛔ **AND ONE OF THOSE FOUR WAS GRADED GREEN WHILE IT WAS RED ON THIS SLICE'S OWN TREE
//     (#808).** Claim 3's real-body needle was `contains("your body")`; the sentence `7e906cd`
//     shipped in the SAME commit reads "toward your measured **body state**". It never matched.
//     The block two bullets up names the exact risk that produced this — the bundle does not
//     compile against the parent, so "every bullet below is a hand-transcription" — and the
//     hand went wrong in the harshest direction available: not a wrong verdict on the PARENT,
//     which is what §3 warns about, but a wrong verdict on the tree the commit shipped.
//     **Transcribing a needle is not driving it.** Claim 3 is REGRESSION as of #808 and is now
//     driven, control plus five mutations, with the shipped strings read out of the Swift
//     source rather than retyped. It stayed invisible for two months because of #807: the CI
//     job log carries only `tail -200 test.log`.
//   · **3 COUNTERWEIGHTS, green on both trees — the three form-bans**, which keep the
//     element-label, the spoken-prefix and the section-head spellings out of these rows.
//     (Claim 4's "no unfed channel" loop is FORWARD, not a counterweight — it drives a static
//     this commit creates, so it has no verdict on the parent.)
//   · ⛔ **A CLAIM 5c WAS RETIRED MID-SLICE.** It scanned the studio view for the
//     disabled-branch sentence; once `autoModeCaption` took the frame, that sentence moved OUT
//     of the view and the scan was red on this slice's own correct tree (#364). The FACT it
//     protected is not lost — the no-frame branch is driven by claim 3 and by claim 4's
//     `for: nil` needle, END-TO-END rather than scanned, which is stronger.
//   · ⭐ **AND THE TOTAL DID NOT MOVE, WHICH IS WHY IT WAS RE-DERIVED INSTEAD OF ADJUSTED.**
//     Subtracting the retired claim from the printed nine would have given eight — and eight is
//     wrong, because the enumeration behind the nine was ALSO wrong: it said "the two form-bans"
//     where the loop carries THREE spellings. Two errors of one, in opposite directions,
//     cancelling to the right total by accident. 5a + 5b + 3 form-bans + claim 6's four = **9**.
//   · **Stripper: PROPHYLAKTISCH — 0 of the 9 scan verdicts flip, on either tree** (18 raw-vs
//     stripped comparisons, both trees, all identical). DRIVEN, not
//     predicted: three cycles running my TRAGEND predictions were wrong, and the reason is
//     structural rather than accidental — a well-built needle carries its call context or its
//     surrounding quotes, and is therefore NARROWER than the prose that quotes the bare phrase.
//     Good needle design and a prophylactic stripper are the same fact seen twice.
//
// ⚠️ #364: a different honest shape is not forbidden. Marking at the panel instead of per row,
// dropping the possessive from both captions, or folding the source into the toggle's label
// would all satisfy the law and turn claims 5/6 red — that is the moment to rewrite this file.
// What is forbidden silently is a row that qualifies itself on one axis and lets the reader
// conclude it qualified itself on all of them.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBioPanelRowsSayWhoseBodyTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - 1–4  the four sentences, driven

    /// 1 — FORWARD. The breath hint names its subject in all three states.
    func testTheBreathHintNamesItsSubject() {
        XCTAssertTrue(BioPanelRowCopy.breathVoiceHint(for: Self.frame(.cameraPPG))
                        .contains("your body"), """
            The real-body hint lost the founder's phrase. It is TRUE when a body is being read; \
            only the other two states move.
            """)
        let demo = BioPanelRowCopy.breathVoiceHint(for: Self.frame(.fallback))
        XCTAssertTrue(demo.contains("the simulated demo source") && demo.contains("not your body"),
                      """
            The demo hint no longer names the demo generator, or dropped the explicit \
            exclusion. Arming under Simulation colours the tone from fabricated numbers.
            """)
        XCTAssertFalse(BioPanelRowCopy.breathVoiceHint(for: nil).contains("your body"), """
            With nothing measured the hint names a body again. Arming still sounds the tone — \
            its colour simply will not move — so the honest sentence says that, not "follows \
            your body".
            """)
    }

    /// 2 — FORWARD. The breath caption carries BOTH axes: whose reading, and whether breath is
    /// arriving. The four combinations must stay distinguishable.
    func testTheBreathCaptionCarriesBothAxes() {
        let bodyBreath = BioPanelRowCopy.breathVoiceCaption(for: Self.frame(.cameraPPG))
        let demoBreath = BioPanelRowCopy.breathVoiceCaption(for: Self.frame(.fallback))
        XCTAssertNotEqual(bodyBreath, demoBreath, """
            The caption reads identically for a real body and for the demo generator. The \
            source axis is the one #648 added; if it collapses, the row is back to conditioning \
            on breath alone and reading as if it conditioned on everything.
            """)
        for text in [bodyBreath, demoBreath] {
            XCTAssertTrue(text.contains("inhale opens it"), """
                A breath-measured caption stopped promising the inhale/exhale gating. That is \
                the fact the breath axis exists to state, and it must survive the source axis.
                """)
        }
        // ⛔ NO CLAIM COVERED `breathVoiceCaption(for: nil)` AND IT WAS THE WORST STRING IN THE
        // SLICE. It rendered "…follows the heart and coherence of nothing yet. No breathing
        // measured yet…" — ungrammatical, "yet" twice, and it CONTRADICTED the hint on the same
        // control in the same state ("its colour will not move"). Two sentences on one row
        // disagreeing is the #616b class the row's own comment cites. And this is the state the
        // Bio panel is in MOST often: before Play, before a source is chosen. The hint's nil
        // branch was tested and the caption's was not — asymmetric coverage over one pair.
        let nothing = BioPanelRowCopy.breathVoiceCaption(for: nil)
        XCTAssertFalse(nothing.contains("your body") || nothing.contains("nothing yet"), """
            The no-frame caption names a body, or renders the "of nothing yet" genitive. \
            Nothing has been measured, so the honest sentence is future-tense about what WILL \
            follow — and it must agree with the hint beside it, which says the colour will not \
            move.
            """)
        let noBreath = BioPanelRowCopy.breathVoiceCaption(for: Self.frameNoBreath(.cameraPPG))
        XCTAssertTrue(noBreath.contains("No breathing measured yet"), """
            The no-breath caption stopped saying so. Without onsets nothing closes the \
            envelope, so a caption promising inhale/exhale gating would describe a permanent \
            drone — the class this row's own doc says the repo keeps paying for.
            """)
    }

    /// 3 — REGRESSION. The Auto-mode hint answers even while the control is disabled, because
    /// VoiceOver reads hints on disabled controls.
    ///
    /// ⛔ THIS CLAIM WAS RED FROM BIRTH AND STAYED RED FOR TWO MONTHS. Its real-body needle was
    /// `contains("your body")`; the sentence #648 shipped in the same commit (`7e906cd`, proved
    /// with `git log -S` on both halves) reads "toward your measured **body state**". The
    /// sentence was never wrong — it names the reader's body, in a different word order — so the
    /// repair is the NEEDLE, and claim 6 below independently pins that literal as the intended
    /// copy. What made it invisible is #807: the CI job log carries only `tail -200 test.log`,
    /// so a failure has to land inside the last 200 lines to be seen at all. It surfaced the day
    /// that window was measured, not the day it broke.
    ///
    /// ⭐ THE ROOT IS MEASURABLE AND IT IS NOT "a copied needle". Every OTHER `contains("your
    /// body")` in this file is green, and the reason is structural: `breathVoiceHint` builds its
    /// sentence through `BioPanelRowCopy.subject(synthetic:)`, the shared helper whose real-body
    /// branch IS the literal "your body". `autoModeHint` is the one static that does not call
    /// that helper — it spells its own sentence, because it carries "measured … state", which
    /// the helper cannot express. **The one sentence that bypassed the shared subject is the one
    /// sentence whose needle missed.** The divergence is deliberate copy, so the guard asks for
    /// the sentence this static actually has; the demo half now asks
    /// `BioProvenanceCopy.demoSubject` (the one definition, #416) instead of re-spelling a
    /// fragment of it.
    ///
    /// ⚠️ WHAT THIS DOES NOT DO: it does not route `autoModeHint` through `subject(synthetic:)`.
    /// That would be a user-facing copy change on a red-gate fix, and it would drop "the measured
    /// state of" from the demo branch. If a later slice wants one path, that is a copy decision
    /// with a founder in it, not a needle repair.
    func testTheAutoModeHintAnswersInEveryState() {
        let real = BioPanelRowCopy.autoModeHint(for: Self.frame(.healthKit))
        XCTAssertTrue(real.contains("your measured body state"), """
            The real-body Auto hint lost its subject. A hint that steers "the mood dials" without
            saying whose reading moves them is the exact ambiguity this file exists to close.
            """)
        XCTAssertFalse(real.contains(BioProvenanceCopy.demoSubject), """
            The real-body Auto hint carries the demo subject. Counterweight to the assertion
            above: naming a body is only half the claim — it has to be the RIGHT body, and this
            asks the one definition rather than a second spelling of it.
            """)
        XCTAssertTrue(BioPanelRowCopy.autoModeHint(for: Self.frame(.fallback))
                        .contains(BioProvenanceCopy.demoSubject), """
            The Auto hint promises to steer toward a body while the demo generator is the only
            thing being measured.
            """)
        let none = BioPanelRowCopy.autoModeHint(for: nil)
        for presentTenseClaim in ["your body", "your measured"] {
            XCTAssertFalse(none.contains(presentTenseClaim), """
                With no source the hint claims a present measurement (\(presentTenseClaim)). The
                control is disabled in that state, but a hint is still spoken on a disabled
                control — which is exactly why it needs its own sentence rather than inheriting
                one. Both spellings are banned because banning only the first is how this very
                claim went red unnoticed: a re-worded body claim slips past a single literal.
                """)
        }
    }

    /// 4 — FORWARD. The Auto caption marks its subject and promises only fed channels.
    func testTheAutoCaptionMarksItsSubjectAndPromisesOnlyFedChannels() {
        let demo = BioPanelRowCopy.autoModeCaption(for: Self.frame(.fallback))
        XCTAssertTrue(demo.contains("not your body"), """
            The enabled Auto caption still promises to steer toward the reader's body under \
            Simulation. This is the branch that renders whenever a frame exists, and the demo \
            generator produces frames.
            """)
        XCTAssertTrue(BioPanelRowCopy.autoModeCaption(for: Self.frame(.cameraPPG))
                        .contains("your body"), "The real-body Auto caption lost its subject.")
        // The third state, which this function could not express while it took a `Bool` (#644).
        let none = BioPanelRowCopy.autoModeCaption(for: nil)
        XCTAssertFalse(none.contains("your body"), """
            The no-source Auto caption names a body. Nothing is being measured and the toggle \
            is disabled in that state, so the sentence must say what is missing, not whose \
            reading would be steered toward.
            """)
        XCTAssertTrue(none.contains("Bio source control above"), """
            The no-source caption stopped naming the route. #616b: it once taught a long-press \
            three rows BELOW the visible "Bio source" row, so two captions in one panel \
            disagreed about how to start a source.
            """)
        // ⛔ THIS LIST WAS THREE AND THE GUARD IT SUPERSEDES BANNED FIVE. #648 moved the caption
        // out of `AutoModeRow`, which made `AutoModeStartsOffAndOwnsNoTempoTests`' five-word ban
        // scan text it no longer sees — green for a reason that stopped existing (§4) — and the
        // replacement here silently dropped "valence" and "emotion". Both files now drive the
        // pure static, and both carry the full five. A superseding guard has to be a SUPERSET,
        // or the commit that adds coverage removes some.
        for banned in ["breath depth", "LF/HF", "trend", "valence", "emotion"] {
            for source in [Self.frame(.fallback), Self.frame(.cameraPPG)] {
                XCTAssertFalse(BioPanelRowCopy.autoModeCaption(for: source)
                                .contains(banned), """
                    The Auto caption promises "\(banned)". #496 measured that it has NO producer \
                    — both `PolyBioParams` construction sites pin it to a literal — so naming it \
                    is a claim about a channel nothing feeds. A sentence about "your measured \
                    state" is exactly where these grow back.
                    """)
            }
        }
    }

    // MARK: - 5–6  the wiring, and what must not change

    /// 5a/5b — REGRESSION. The three form-bans — COUNTERWEIGHT.
    /// (A claim 5c stood here and was retired mid-slice; the header says why.)
    func testTheRowsAskTheOneDefinitionAndKeepWhatMustNotMove() throws {
        let code = try codeText(Self.studio)
        XCTAssertFalse(code.contains("\"Sounds a held tone whose colour follows your body\""), """
            `BreathVoiceRow` speaks the fixed hint again. Its three forms belong to \
            `BioPanelRowCopy.breathVoiceHint(for:)`; a literal here is a second definition \
            (#416) and, on the shipped tree, was the unconditional one.
            """)
        XCTAssertFalse(
            code.contains("\"Slowly steers the mood dials toward your measured body state\""), """
            `AutoModeRow` speaks the fixed hint again. Same reason as the breath hint above.
            """)
        // ⛔ A CLAIM 5c SCANNED THE STUDIO VIEW FOR THE DISABLED-BRANCH SENTENCE, and the same
        // review pass that made `autoModeCaption` take the frame MOVED that sentence into the
        // pure type — so my own guard went red on my own correct tree, one edit after I
        // re-anchored two OTHER guards for exactly that reason. Retired rather than re-pointed:
        // claim 4 now DRIVES both halves of it (no body named, and the "Bio source control
        // above" route still taught), which is strictly stronger than any scan (§1).
        // ⛔ The first draft wrote this as `contains(form) && contains("BioPanelRowCopy")`,
        // which goes vacuously green the day the type is renamed — #454's shape. Measured:
        // both other forms occur ZERO times in this file, so a plain ban is the honest test.
        // ⛔ THIS LIST WAS TWO AND THE DOCUMENTED CENSUS IS THREE. `"demo values, not your
        // body"` (the section HEAD) was unguarded while the header claimed the census was
        // complete — and the header had itself substituted "mid-sentence subject" for the head,
        // making this helper a de-facto FOURTH form that called itself one of three. Three
        // spellings banned here; the fourth is what these rows use.
        for form in ["Bio source: simulated demo", "Simulated demo, ", "demo values, not your body"] {
            XCTAssertFalse(code.contains(form), """
                The "\(form)" spelling appeared in the studio view. Three forms exist for three \
                jobs — element label (strip · widget · watch), spoken prefix, and the \
                mid-sentence subject these rows take. Collapsing them is #634b; if a NEW row \
                here legitimately needs one of the other two, retire this claim rather than \
                weakening it.
                """)
        }
    }

    /// 6a–6d — REGRESSION (ONE absence, reported four times — #486). Both rows ask the pure
    /// type, and the loop carries four needles, not two.
    func testBothRowsRenderThePureCopy() throws {
        let code = squeezed(try codeText(Self.studio))
        for needle in ["BioPanelRowCopy.breathVoiceHint(for:frame)",
                       "BioPanelRowCopy.breathVoiceCaption(for:frame)",
                       "BioPanelRowCopy.autoModeHint(for:frame)",
                       "BioPanelRowCopy.autoModeCaption(for:frame)"] {
            XCTAssertTrue(code.contains(needle), """
                `\(needle)` is gone from the studio view. A row that builds its own sentence is \
                free to drift from the three the type owns, which is the whole defect #648 \
                removed.
                """)
        }
    }

    // MARK: - helpers

    private struct RowAnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    /// A frame with a plausible breath rate, so `hasMeasuredBreath` is true.
    private static func frame(_ source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: 60, hrvNormalized: 0.4,
                       breathRate: 12, breathPhase: 0.25,
                       coherence: 0.7, motionEnergy: 0, source: source)
    }

    /// The same frame with NO plausible breath rate — the second axis of claim 2.
    ///
    /// ⚠️ `breathRate: 45`, ABOVE the range, not `0` below it. `plausibleBreathRate` is `3...40`,
    /// so a zero fixture cannot tell `hasMeasuredBreath` apart from a re-inlined `breathRate > 0`
    /// — and `OSCSender` records that exact re-inlining having happened once already. 45 is
    /// non-zero and implausible, so only the shared accessor gives the right answer.
    private static func frameNoBreath(_ source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: 60, hrvNormalized: 0.4,
                       breathRate: 45, breathPhase: 0,
                       coherence: 0.7, motionEnergy: 0, source: source)
    }

    private func squeezed(_ code: String) -> String { code.filter { !$0.isWhitespace } }

    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RowAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
