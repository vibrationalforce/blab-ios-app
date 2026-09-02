// TheAlwaysOnChannelsAreShownTests.swift
// Echoel — #498. The always-on half of "body → sound" stops being a SENTENCE and becomes a READOUT.
//
// #496 removed a false empty state and added a sentence naming the four channels that shape the
// instrument's own timbre. #497 then made those four honest at the engine boundary — an unmeasured
// channel hands over the engine's declared neutral (0.5) instead of an extreme. Together those two
// created a gap that neither of them could close alone: from outside, a neutral 0.50 and a body
// sitting mid-scale are the SAME NUMBER. For heart rate they are literally the same number —
// 120 bpm normalises to exactly 0.5 by construction. A value alone can no longer say which it is.
//
// So this slice shows both facts together, and half the file exists to keep them together.
//
// ⭐ THE ENABLING HALF IS A #416 FIX, and it is what makes the switch in `AlwaysOnBioChannel` a
// LOOKUP rather than a third copy of a rule. Two of the four channels already had a NAMED gate
// (`hasMeasuredHeartRate`, `hasMeasuredBreath`); the other two carried a bare `> 0` inline inside
// their own accessor. That asymmetry was invisible while nothing but the accessor asked the
// question — the moment a second reader appeared it would have written the comparison a third
// time. `hasMeasuredHRV` / `hasMeasuredCoherence` are named here and the accessors now ask them.
//
// ⭐ AND THE `shapes` COPY IS READ OFF THE ENGINE, NOT OFF CLAUDE.md. That table is one-to-one
// (coherence → harmonicity, HRV → brightness, heart rate → vibrato, breath phase → envelope);
// `applyBioReactive` is not — coherence alone moves the filter cutoff, brightness, harmonicity AND
// the noise level. Building the rows from the table would have shipped a fresh UNDER-statement onto
// the one surface #496 just corrected for over-statement, which is #439's mistake in the other
// direction. The measurement is in the type's file header.
//
// ⚠️ THE LIMIT FIRST. The BEHAVIOUR half here is real end to end: `BioSampleFrame` and
// `AlwaysOnBioChannel` are `public` Foundation-only value types, so every neutral/measured case
// below drives the shipped code. The MOUNT half is a SOURCE SCAN — `AlwaysOnBioView` is `private`
// inside a SwiftUI view this bundle cannot instantiate. That the section renders, that four rows
// fit the sheet at accessibility sizes, that VoiceOver reads the two facts in a useful order, and
// that a player learns anything from watching it are four device checks and all four are open.
//
// ⚠️ HONEST GRADING against the pre-#498 tree, hand-transcribed because the bundle CANNOT be
// compiled against it (#464's situation, said plainly): every behaviour case names
// `AlwaysOnBioChannel`, which does not exist there, so NO assertion in this file has a verdict on
// that tree. What CAN be graded is the source text the three scans read, and it was — by
// transcribing `SourceText.codeOnly` in Python and running all ten needles against `git show HEAD:`
// and against the working tree, rather than reasoning about them:
//   · TWO are red for their NAMED reason. `testTheTwoUnnamedGatesAreNamedAndTheAccessorsAskThem`:
//     all six needles fail on HEAD (both gates unnamed, both accessors carrying the inline
//     comparison — the negative needles each match once there). `testTheReadoutIsMountedInTheFXForm`:
//     both needles fail.
//   · ONE is red by ANCHOR ABSENCE, which is a different thing and is counted as such (#486).
//     `testTheLiveReadStaysInTheLeafAndNotInTheSheetBody` hits its own `XCTFail("anchors missing")`
//     because the leaf does not exist on HEAD — that is ONE absence, not a finding about the
//     freeze law. Booking it with the two above would inflate the count by a third.
//   · The SEVEN behaviour cases drive a type this same commit creates. They could never have been
//     red, and booking them as regressions would be the #433 defect in the flattering direction.
//     Their whole value is FORWARD: four of them are labelled COUNTERWEIGHT below and exist to make
//     the obvious later "cleanups" fail — reading the raw field instead of the `…ForSound` accessor,
//     collapsing measured-ness into "value != 0.5", loosening a gate to `!= 0`, or folding the rows
//     into `EchoelFXView.body` (the freeze law, which no compiler enforces).
//
// ⛔ `SourceText.codeOnly` IS LOAD-BEARING HERE, and the first draft of this header called it
// prophylactic with a needle count that was wrong in both parts — the exact over-claim #484 and
// #485 each had to retract once and #486 twice, repeated in the file that cites them. MEASURED, not
// assumed: stripped vs raw differ on **1 of 10** needle verdicts, and the one that differs is
// `testTheLiveReadStaysInTheLeafAndNotInTheSheetBody`. Raw, the sheet half holds `latestBio` FOUR
// times — every one of them in a `///` block this same slice writes, explaining why the leaf reads
// that snapshot and not `usableBio()`. A raw-text scan would therefore be RED ON CORRECT CODE. It is
// the #486/#491 collision once more: this repo writes down what it does, so a negative scan meets
// its own rationale unless something separates code from prose.

import XCTest
@testable import Echoelmusic

final class TheAlwaysOnChannelsAreShownTests: XCTestCase {

    private static let fxView = "Sources/Echoelmusic/Studio/EchoelFXView.swift"
    private static let bus = "Sources/Echoelmusic/Core/EngineBus.swift"

    /// Reads a repo source file as CODE, never prose (#453). Skips on the DIRECTORY, never on the
    /// individual file: a `fileExists` bracket around each read turns a deletion — the exact
    /// catastrophe this bundle stands against — into a green skip (#475).
    private func code(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: sources.path),
                          "Sources/ not present in this checkout")
        let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        XCTAssertFalse(text.isEmpty, "\(relative) is empty — the scan below would pass on nothing")
        return SourceText.codeOnly(text)
    }

    private func frame(hr: Float = 0, hrv: Float = 0, coh: Float = 0,
                       breathRate: Float = 0, breathPhase: Float = 0) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1, heartRateBPM: hr, hrvNormalized: hrv,
                       breathRate: breathRate, breathPhase: breathPhase,
                       coherence: coh, motionEnergy: 0, source: .cameraPPG)
    }

    // MARK: - Behaviour: the neutral is visible AS a neutral

    func testAnEmptyFrameReportsAllFourAsUnmeasuredAtTheNeutral() {
        let f = frame()
        for channel in AlwaysOnBioChannel.allCases {
            XCTAssertFalse(channel.isMeasured(in: f),
                           "\(channel.name) claims a measurement on a frame that carries none")
            XCTAssertEqual(channel.value(in: f), 0.5, accuracy: 1e-6,
                           "\(channel.name) must hand the engine its declared neutral when unmeasured")
        }
    }

    func testAFullyMeasuredFramePassesEveryChannelThrough() {
        let f = frame(hr: 60, hrv: 0.4, coh: 0.7, breathRate: 12, breathPhase: 0.25)
        for channel in AlwaysOnBioChannel.allCases {
            XCTAssertTrue(channel.isMeasured(in: f), "\(channel.name) should be measured here")
        }
        // 60 bpm -> (60-40)/160 = 0.125; the others pass through unchanged.
        XCTAssertEqual(AlwaysOnBioChannel.heartRate.value(in: f), 0.125, accuracy: 1e-6)
        XCTAssertEqual(AlwaysOnBioChannel.hrv.value(in: f), 0.4, accuracy: 1e-6)
        XCTAssertEqual(AlwaysOnBioChannel.coherence.value(in: f), 0.7, accuracy: 1e-6)
        XCTAssertEqual(AlwaysOnBioChannel.breathPhase.value(in: f), 0.25, accuracy: 1e-6)
    }

    /// THE SHARPEST CASE, and the reason the row shows two facts instead of one: 120 bpm normalises
    /// to EXACTLY the neutral. A surface that inferred "unmeasured" from the value would call a
    /// measured 120-bpm heart unmeasured, and a readout that inferred "measured" from a non-zero
    /// value would call the neutral a reading. Only the gate can tell them apart.
    func testAMeasuredChannelThatHappensToReadNeutralIsStillMeasured() {
        let f = frame(hr: 120, breathRate: 12, breathPhase: 0.5)
        XCTAssertEqual(AlwaysOnBioChannel.heartRate.value(in: f), 0.5, accuracy: 1e-6,
                       "120 bpm is the neutral by construction — if this moved, the premise moved")
        XCTAssertTrue(AlwaysOnBioChannel.heartRate.isMeasured(in: f))
        XCTAssertTrue(AlwaysOnBioChannel.breathPhase.isMeasured(in: f))
    }

    /// COUNTERWEIGHT. The obvious later simplification is "drop `isMeasured`, just compare against
    /// 0.5". This pins the two apart in BOTH directions on every channel.
    func testMeasurednessIsNeverInferredFromTheValue() {
        let neutralButMeasured = frame(hr: 120, hrv: 0.5, coh: 0.5, breathRate: 12, breathPhase: 0.5)
        for channel in AlwaysOnBioChannel.allCases {
            XCTAssertTrue(channel.isMeasured(in: neutralButMeasured),
                          "\(channel.name) reads 0.5 here from a REAL body, not from absence")
            XCTAssertEqual(channel.value(in: neutralButMeasured), 0.5, accuracy: 1e-6)
        }
    }

    /// COUNTERWEIGHT. `> 0` and not `!= 0`: a negative normalised value is a corrupt frame, and
    /// calling it "measured" is the failure direction this whole family exists to avoid.
    func testACorruptNegativeReadingIsNotCalledAMeasurement() {
        let f = frame(hr: -60, hrv: -0.2, coh: -0.9)
        XCTAssertFalse(AlwaysOnBioChannel.hrv.isMeasured(in: f))
        XCTAssertFalse(AlwaysOnBioChannel.coherence.isMeasured(in: f))
        XCTAssertFalse(AlwaysOnBioChannel.heartRate.isMeasured(in: f))
        for channel in AlwaysOnBioChannel.allCases {
            XCTAssertEqual(channel.value(in: f), 0.5, accuracy: 1e-6,
                           "\(channel.name) must fall to the neutral, never pass a corrupt value on")
        }
    }

    /// COUNTERWEIGHT against the tidy-looking mistake of describing all four with one target each,
    /// the way CLAUDE.md's table does. Coherence moves four things and the copy has to say so.
    func testTheCopyDoesNotCollapseTheEngineIntoOneTargetPerChannel() {
        XCTAssertTrue(AlwaysOnBioChannel.coherence.shapes.contains("filter"))
        XCTAssertTrue(AlwaysOnBioChannel.coherence.shapes.contains("harmonicity"))
        XCTAssertTrue(AlwaysOnBioChannel.heartRate.shapes.contains("vibrato"))
        XCTAssertTrue(AlwaysOnBioChannel.hrv.shapes.contains("brightness"))
        for channel in AlwaysOnBioChannel.allCases {
            XCTAssertFalse(channel.shapes.isEmpty, "\(channel.name) must say what it shapes")
            XCTAssertFalse(channel.name.isEmpty)
        }
    }

    /// COUNTERWEIGHT. The inputs `applyBioReactive` takes that are pinned to literals at both
    /// construction sites must stay OUT of this list — naming them is the over-claim #496 removed.
    ///
    /// ⛔ #979 — THIS CLAIM BANNED `"trend"` AND ITS STATED REASON HAS BEEN FALSE SINCE #813.
    /// The message read *"'trend' has no producer — listing it would re-open the #496 over-claim"*.
    /// `coherenceTrend` GOT a producer at #813: `Core/CoherenceTrend`, one run per source, and
    /// BOTH `…BioParams(` sites now pass `coherenceTrend: trend` instead of the literal 0
    /// (`TheAlwaysOnBioPathIsNamedTests.testBothProducersDeriveTheFourAndPinTheThree` pins exactly
    /// that, so it is not restated here — #416). The consumer is reachable too: the rising/falling
    /// spectral morph in `EchoelDDSP.applyBioReactive` reads it behind nothing but its own
    /// deadband — no dead flag in front of it, which is the #546 test.
    ///
    /// So this was BOTH failure modes at once, in one assertion:
    ///   · #367 — it could only ever fail for a reason that is not true any more.
    ///   · #364 — worse, it FORBADE CORRECT WORK. The day someone rightly names the trend on the
    ///     surface, this would go red with a message arguing them back out of it.
    ///
    /// ⭐ AND IT IS THE #766/#456 PATTERN, EXACTLY. #813 did move this permission — it rewrote the
    /// bans in the three copy guards, `docs/overview.html` and `architecture.html`, and it edited
    /// the sibling claim in `TheAlwaysOnBioPathIsNamedTests` with a ⛔ note explaining the move.
    /// It simply did not know this fourth home existed. When every home you checked is the same
    /// KIND, the ENUMERATION is what is incomplete, not the care per entry.
    ///
    /// ⚠️ WHAT IS **NOT** CLAIMED HERE, deliberately: that the trend SHOULD be on the surface.
    /// Naming it is allowed, not required — a copy decision (`EchoelDDSP.applyBioReactive` says so
    /// at the branch). Two things stand in the way today and neither is this test's business:
    /// the trend's scale (`fullScaleRisePerSecond`) is an unverified estimate carrying a
    /// NEEDS-FOUNDER-VERIFY, so nobody has confirmed the morph is audible; and there is no single
    /// published trend to READ — each voice owns its own `CoherenceTrend`, and only
    /// `PolySynthVoice` gates its feed on `bioModulationEnabled`, so the two are not the same
    /// value. A fifth ROW needs that resolved first. The valence rule binds any such copy
    /// whenever it comes: rising coherence is an ENGINEERING mapping, never "purer" or "calmer".
    func testThePinnedChannelsAreStillAbsent() {
        let names = AlwaysOnBioChannel.allCases.map { $0.name.lowercased() }.joined(separator: " ")
        for pinned in ["depth", "lf/hf"] {
            XCTAssertFalse(names.contains(pinned),
                           "'\(pinned)' has no producer — both `…BioParams(` sites still pass it "
                           + "as a literal, so listing it would re-open the #496 over-claim")
        }
    }

    /// #979 — what replaces the trend ban: the ENUMERATION and the COPY may not drift apart.
    ///
    /// The old claim tried to keep one specific channel off the surface. The durable property is
    /// weaker and more useful: both always-on sentences open by COUNTING the channels ("four body
    /// channels shape …"), and that word is written by hand while the list comes from
    /// `allCases`. Adding a fifth case — the trend, or anything else — without touching the copy
    /// ships a sentence that undercounts what the body moves, on the one surface #496 had to
    /// repair for the opposite mistake. This permits the fifth channel and forbids the half-step.
    ///
    /// ⚠️ It asserts the sentences AGREE with the count, never that the count is 4. A guard that
    /// froze the number would be the #364 defect this file just removed one of.
    func testBothAlwaysOnSentencesCountTheChannelsTheyList() {
        let words = [2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven"]
        let n = AlwaysOnBioChannel.allCases.count
        guard let expected = words[n] else {
            return XCTFail("\(n) channels — extend the number-word table above before shipping "
                           + "a count this file cannot spell")
        }
        let sentences = [
            ("alwaysOnSentence", AlwaysOnBioChannel.alwaysOnSentence(synthetic: false)),
            ("alwaysOnSentence(demo)", AlwaysOnBioChannel.alwaysOnSentence(synthetic: true)),
            ("bioPanelSentence", AlwaysOnBioChannel.bioPanelSentence(synthetic: false)),
            ("bioPanelSentence(demo)", AlwaysOnBioChannel.bioPanelSentence(synthetic: true))
        ]
        for (label, text) in sentences {
            let lower = text.lowercased()
            XCTAssertTrue(lower.contains(expected),
                          "\(label) does not say '\(expected)' while `allCases` holds \(n) "
                          + "channels. The count is written by hand and the list is not — update "
                          + "the sentence in the same commit as the case.")
            for (other, word) in words where other != n {
                XCTAssertFalse(lower.contains(" \(word) "),
                               "\(label) still says '\(word)' while `allCases` holds \(n). Two "
                               + "counts in one sentence is worse than a stale one.")
            }
        }
    }

    // MARK: - Wiring (source scans)

    func testTheTwoUnnamedGatesAreNamedAndTheAccessorsAskThem() throws {
        let src = try code(Self.bus)
        XCTAssertTrue(src.contains("public var hasMeasuredHRV: Bool"),
                      "the HRV gate must have a name a second reader can ask")
        XCTAssertTrue(src.contains("public var hasMeasuredCoherence: Bool"),
                      "the coherence gate must have a name a second reader can ask")
        XCTAssertTrue(src.contains("hasMeasuredHRV ? Swift.min(hrvNormalized, 1) : 0.5"),
                      "hrvForSound must ASK the gate, not restate the comparison (#416)")
        XCTAssertTrue(src.contains("hasMeasuredCoherence ? Swift.min(coherence, 1) : 0.5"),
                      "coherenceForSound must ASK the gate, not restate the comparison (#416)")
        XCTAssertFalse(src.contains("hrvNormalized > 0 ? Swift.min"),
                       "the inline copy is back — that is the third-copy drift #416 names")
        XCTAssertFalse(src.contains("coherence > 0 ? Swift.min"),
                       "the inline copy is back — that is the third-copy drift #416 names")
    }

    func testTheReadoutIsMountedInTheFXForm() throws {
        let src = try code(Self.fxView)
        XCTAssertTrue(src.contains("AlwaysOnBioView()"),
                      "the section exists but nothing renders it — a doorless readout is not a readout")
        XCTAssertTrue(src.contains("private struct AlwaysOnBioView: View"),
                      "it must be its own View struct: the freeze law is what makes the bio read safe here")
    }

    /// THE FREEZE-LAW COUNTERWEIGHT, and the one assertion here that no compiler can make. The bio
    /// read is legal ONLY because it happens inside a leaf's own body. Folding these four rows up
    /// into `EchoelFXView.body` — "it's only four rows" — registers the whole sheet as an observer
    /// and tears down the `.menu` Pickers above on every frame (10.76.41/50).
    ///
    /// ⚠️ SAY WHAT THE SLICE ACTUALLY COVERS, because the name understates it: the first half runs
    /// from `EchoelFXView` to `AlwaysOnBioView`, so it covers every declaration in between —
    /// `BioModLiveView` and the other private leaves as well as the sheet body itself. That is the
    /// SAFE direction (it forbids the read in more places than the freeze law strictly requires),
    /// but it means a future leaf in that span which legitimately needs `latestBio` will turn this
    /// red. That is a decision to make deliberately, not a bug to route around by deleting the scan.
    func testTheLiveReadStaysInTheLeafAndNotInTheSheetBody() throws {
        let src = try code(Self.fxView)
        guard let structRange = src.range(of: "struct EchoelFXView: View"),
              let leafRange = src.range(of: "private struct AlwaysOnBioView: View") else {
            return XCTFail("anchors missing — this scan would pass on nothing")
        }
        let sheet = String(src[structRange.lowerBound..<leafRange.lowerBound])
        XCTAssertFalse(sheet.contains("latestBio"),
                       "a live bio read escaped into the sheet body — that is the menu-freeze regression")
        let leaf = String(src[leafRange.lowerBound...])
        XCTAssertTrue(leaf.contains("bus.latestBio"),
                      "the leaf must read the SAME snapshot the sound producers read, not usableBio()")
    }
}
