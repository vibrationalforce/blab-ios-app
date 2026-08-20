// TheSpokenTempoSaysWhoseBodyTests.swift
// Echoel — #647: the tempo field SHOWED a discriminator and SPOKE none.
//
// WHAT THIS GUARDS. `BodyTempoField`'s unlocked readout tints accent while a pulse is driving
// it, so a sighted player gets a signal. Its VoiceOver label was the fixed string
// `"Tempo, driven by your body"` in every state — and the clock it describes is driven through
// `BioComposer.tempo(for:)` from the composer input, i.e. from `bus.usableBio()`. Under the
// Simulation source that is the demo generator's fabricated frame; with no usable frame it is
// whatever the clock was last set to. So a VoiceOver player on a demo session was told their
// body was driving the tempo.
//
// ⭐ THE #632/#627b PATTERN — the visible half marked, the spoken half not. Worth stating why
// that asymmetry keeps happening: a marking gets added where it is SEEN during the change, and
// speech is not seen.
// ⛔ THIS SAID "the LAST registered entry of it in this family" AND THAT WAS FALSE (#647
// review). Both registers still list open entries and at least one is SPOKEN:
// `EchoelStudioView`'s `.accessibilityHint("Sounds a held tone whose colour follows your body")`
// — which one register names as "the #632/#627b pattern exactly". Declaring a pattern closed is
// how the next session stops looking for it, so it is the most expensive kind of flattering
// sentence this family can write.
//
// ⚠️ THE KEYING IS THE WHOLE SLICE, and the tempting cheap version is wrong. This file has a
// `liveBodyBPM` flag already, and keying the sentence on it costs nothing — but it is
// camera-only (`cameraRPPG.isRunning && displayBPM > 0`), so it would announce "not your body"
// to a player whose BLE strap or Apple Watch is driving the clock. That is an over-correction,
// which is this family's remaining risk and what it has already had to retract twice. Claim 4
// pins that the label does NOT ask that flag.
//
// ⚠️ THE VISIBLE TINT IS DELIBERATELY LEFT ALONE and its imprecision is registered at the flag
// rather than fixed here. The tint means "the camera is locked on"; the label means "whose
// reading drives the clock". They answer different questions on purpose, and the tint must not
// be repointed at a wider predicate because its reason for existing is to stay byte-wise in
// step with `PulseMonitorMiniLive` (#484). Widening it is a separate, visual slice.
//
// ⚠️ ONE OF THE TWO LABEL SITES IS UNREACHABLE. `BodyTempoField` has exactly one construction
// and it passes `compact: true`, so the wide arm never renders. Both sites are fixed anyway —
// a doorless arm that disagrees with its reachable twin is how the next session re-learns the
// wrong sentence from the file it is editing.
//
// ⭐ WHY NOT `BioNarrationDriver`, which already owns "a real body / the demo generator /
// nobody" (#644). Considered and rejected on ONE measured difference: its `nothing` rule is "the
// SUMMARY measured no channel" (`BioExplanation.driver` tests arousal/steadiness/breath), and
// the question here is "is a usable frame ARRIVING at all". A frame carrying a heart rate but no
// breath is `nothing` under that rule and `body` under this one — and for a clock fed by
// `usableBio()` this rule is the right one. Two rules, two surfaces, stated rather than left to
// look like a fourth spelling of one state machine (#416).
//
// KIND (§1): **MIXED.** Claims 1–3 DRIVE `TempoFollowLabel.spoken(for:)`, a pure static above
// this file's `#if canImport(SwiftUI)` guard — END-TO-END, the strong kind, and available only
// because the strings were hoisted out of the `View`. Claims 4–6 are SOURCE-TEXT SCANS:
// `BodyTempoField` is a `@MainActor` `View` this bundle cannot mount. **DEVICE PROBE, open:**
// nobody here can hear VoiceOver speak any of it.
//
// ⚠️ WHAT THIS DOES NOT CLOSE, stated so it is not read as closed. The label answers "what
// would drive the NEXT compose", not "what drove THIS clock value": the tempo is fixed at
// compose time from one `usableBio()` read, and the label takes another at render time. One
// direction is honest understatement (composed from a body, sensor drops, label says nothing is
// driving it — true, the clock is coasting). The other is this slice's own defect inverted:
// composed under Simulation, a real body arrives before the next generate, and the label says
// "your body" over a demo-derived clock until that generate. Closing it means carrying the
// COMPOSED-FROM frame on the take — a data-flow slice, not a copy slice.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (c01393b):
//   · **2 TRUE REGRESSIONS — 5a and 7a.** 7a was added by the review pass: the lock BUTTON
//     spoke the same unconditional body claim 268 lines below the readout, and no register
//     held it. A per-entry list finds what somebody already wrote down; a file-wide sweep
//     for the PHRASE finds what nobody did.
//   · **1 TRUE REGRESSION — 5a.** The fixed string `"Tempo, driven by your body"` genuinely
//     occurs twice in the parent's `View` half, and the claim's named reason is exactly that.
//   · **1 ABSENCE, REPORTED TWICE — 4a and 6** (per-assertion, §3: claim 4 holds two
//     assertions with different verdicts, so "4" alone was the wrong granularity).
//     `TempoFollowLabel` does not exist on the parent,
//     so both needles miss for ONE cause (#486). ⚠️ And since this bundle names that type, it
//     DOES NOT COMPILE against the parent: **no assertion has a verdict there**, and the three
//     bullets are hand-transcriptions of what each needle would find, not run results (§3, the
//     ambiguity that let #488 ship a red gate for a cycle).
//   · **4 FORWARD, BEHAVIOURAL (claims 1, 2, 3 and the three `unlockHint` states of claim 7)**
//     — they drive the two pure statics. Claim 1's loop
//     over six sources is ONE assertion, not six; counting executions is #486's flattering
//     direction wearing arithmetic.
//   · **2 COUNTERWEIGHTS, green on both trees — 4b and 5b.** 4b: the label is not keyed on the
//     camera-only flag, true before and after, and it is the point of the file. 5b: the locked
//     READOUT's label says "Tempo, locked" and claims no body at all, so it needs no marking.
//     ⛔ 5b's note ended "and a sweep for the phrase 'your body' must not invent one for it",
//     WHICH READ AS A LICENCE OVER A STATE THAT WAS NOT CLEAN (#647 review). Such a sweep DID
//     hit a second spoken claim in this file — the lock BUTTON's "tap to let your body drive it
//     again", 268 lines below the readout, reachable by the next VoiceOver swipe, and false
//     under Simulation because unlocking hands the clock to the demo generator. The
//     counterweight protects the locked READOUT and never protected the button; phrasing it as
//     a blanket made it look like it did. Claim 7 covers the button.
//   · **Stripper: PROPHYLAKTISCH — 0 of the 8 scan verdicts flip, on either tree.** (Eight:
//     five, then six when the review pass added claim 6's #408 uniqueness check, then eight
//     when it added claim 7's two. A count in a grading block is only worth writing if it
//     moves with the file it grades.)
//     ⛔ The first draft claimed TRAGEND "on both trees" and named 5a, reasoning that this
//     file's own ⛔ retraction quotes the banned sentence. It does — but 5a's needle is
//     `accessibilityLabel("Tempo, driven by your body")`, the whole CALL, and the prose quotes
//     only the STRING. The needle is narrower than the sentence it protects, so the stripper
//     never has to save it.
//     ⭐ THIS IS THE THIRD CYCLE RUNNING WHERE MEASUREMENT MOVED THIS LABEL, and the three
//     failures have ONE shape worth naming rather than three tallies: I predict TRAGEND from
//     knowing the prose quotes the phrase, and forget that a well-built needle carries its call
//     context and is therefore narrower than the prose. **Carrying the call context is GOOD
//     needle design and is exactly what makes the stripper prophylactic** — the two facts feel
//     opposed and are the same fact. The label is driven, never predicted; §2 asks for the
//     measurement precisely because the intuition here is systematically wrong in one
//     direction. The stripper stays regardless: §2's rule is one stripper, not one
//     load-bearing stripper.
//
// ⚠️ #364: a different honest shape is not forbidden. Dropping the causal clause entirely
// ("Tempo, following"), moving the provenance into `.accessibilityValue`, or marking at the
// row rather than the field would all satisfy the law and turn claims 4/6 red — that is the
// moment to rewrite this file. What is forbidden silently is telling a VoiceOver player that
// their body drives a clock the demo generator is driving.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheSpokenTempoSaysWhoseBodyTests: XCTestCase {

    private static let field = "Sources/Echoelmusic/Studio/BodyTempoField.swift"

    // MARK: - 1–3  the three sentences, driven

    /// 1 — FORWARD. A real body keeps the founder's phrase, word for word.
    func testARealBodyKeepsTheShippedSentence() {
        for source in [BioSource.cameraPPG, .healthKit, .ble, .watch, .oura, .faceCam] {
            XCTAssertEqual(TempoFollowLabel.spoken(for: Self.frame(source)),
                           "Tempo, following your body", """
                \(source) no longer speaks the shipped sentence. It is TRUE when a real body is \
                driving the clock and the phrasing is the founder's; #647 moves the SUBJECT for \
                the other two states and rewrites nothing here. `.faceCam` is included \
                deliberately — it carries no pulse, but it is a real body, and the question this \
                label answers is whose reading drives the clock, not which channel it is.
                """)
        }
    }

    /// 2 — FORWARD. The demo generator is named, and the player's body is explicitly excluded.
    func testTheDemoSourceIsNamedAndTheBodyIsExcluded() {
        let spoken = TempoFollowLabel.spoken(for: Self.frame(.fallback))
        XCTAssertTrue(spoken.contains("simulated demo source"), """
            The demo sentence no longer names the demo generator. Under Simulation the flow \
            servo runs on a fabricated heart rate; a spoken "following your body" over it is \
            the defect #647 removed.
            """)
        XCTAssertTrue(spoken.contains("not your body"), """
            The demo sentence dropped the explicit exclusion. Naming the demo source without \
            it leaves a listener to infer the negative, and every sibling surface in this \
            family states it outright.
            """)
    }

    /// 3 — FORWARD. With no usable frame, nothing is named as driving it.
    func testNoUsableFrameNamesNobody() {
        let spoken = TempoFollowLabel.spoken(for: nil)
        XCTAssertFalse(spoken.contains("your body"), """
            With no usable frame the label names a body again. Nothing is driving the clock \
            from a reading — it sits where it was last put — so naming any body invents a \
            cause. This is the state a `Bool` could not express (#644).
            """)
        XCTAssertTrue(spoken.hasPrefix("Tempo,"), """
            The no-reading label stopped identifying the control. VoiceOver reads the label \
            before the value; dropping "Tempo" leaves the listener with a bare number.
            """)
    }

    // MARK: - 4–6  the wiring, and what must not change

    /// 4 — REGRESSION. Both label sites ask the pure static, and neither asks the camera flag.
    func testBothSitesAskTheOneDefinitionAndNotTheCameraFlag() throws {
        let code = try codeText(Self.field)
        let calls = squeezed(code)
            .components(separatedBy: "accessibilityLabel(TempoFollowLabel.spoken(for:bus.usableBio()))")
            .count - 1
        XCTAssertEqual(calls, 2, """
            The unlocked label is built by \(calls) call(s) to `TempoFollowLabel.spoken`, not \
            two — the compact arm and the wide one. The wide arm is unreachable today, and it \
            is fixed anyway: a doorless arm disagreeing with its reachable twin is how the \
            wrong sentence gets re-learned from the file being edited.
            """)
        XCTAssertFalse(squeezed(code).contains("spoken(for:liveBodyBPM"), """
            The spoken label is keyed on `liveBodyBPM`. That flag is CAMERA-ONLY, so this \
            announces "not your body" to a player whose BLE strap or Watch is driving the \
            clock — the over-correction this family has already retracted twice. Key it on \
            `bus.usableBio()`, the same gate the composer asks.
            """)
    }

    /// 5a — REGRESSION / 5b — COUNTERWEIGHT.
    func testTheFixedStringIsGoneAndTheLockedLabelIsUntouched() throws {
        let code = try codeText(Self.field)
        XCTAssertFalse(code.contains("accessibilityLabel(\"Tempo, driven by your body\")"), """
            The unlocked label is a fixed string again. The three forms belong to \
            `TempoFollowLabel.spoken(for:)`; a literal here is a second definition of one \
            decision (#416) and, on the shipped tree, was the unconditional one.
            """)
        XCTAssertTrue(code.contains("accessibilityLabel(\"Tempo, locked\")"), """
            The LOCKED label changed. It claims no body at all — locking is the moment the \
            number stops being a reading and becomes a setting — so it needs no marking, and a \
            sweep for the phrase "your body" must not invent one for it.
            """)
    }

    /// 6 — REGRESSION. The decision lives in the Foundation-only half, which is why claims 1–3
    /// can drive it at all.
    func testTheDecisionLivesAboveTheSwiftUIGuard() throws {
        let code = try codeText(Self.field)
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // #408: uniqueness is part of WRITING the scan. Without this, a second
        // `#if canImport(SwiftUI)` inserted ABOVE the enum would red the claim below with a
        // message ("moved below the SwiftUI guard") that is false — `firstIndex` would have
        // compared the wrong pair.
        for anchor in ["#if canImport(SwiftUI)", "public enum TempoFollowLabel"] {
            XCTAssertEqual(lines.filter { $0.contains(anchor) }.count, 1,
                           "\(anchor) occurs more than once in \(Self.field)'s code. The "
                           + "ordering claim below uses firstIndex, so a second occurrence "
                           + "makes it compare the wrong pair and fail with a false message.")
        }
        guard let guardAt = lines.firstIndex(where: { $0.contains("#if canImport(SwiftUI)") }),
              let declAt = lines.firstIndex(where: { $0.contains("public enum TempoFollowLabel") })
        else {
            return XCTFail("""
                `public enum TempoFollowLabel` or the `#if canImport(SwiftUI)` guard is gone \
                from \(Self.field) — re-anchor this scan rather than letting it pass on \
                nothing (#454).
                """)
        }
        XCTAssertLessThan(declAt, guardAt, """
            `TempoFollowLabel` moved below the SwiftUI guard. Then it is not Foundation-only, \
            this bundle cannot drive it on a platform without SwiftUI, and claims 1–3 stop \
            being END-TO-END — they become source scans wearing the strong kind's label.
            """)
    }

    /// 7 — REGRESSION. The lock BUTTON speaks the same three states, from the same source.
    ///
    /// ⚠️ A SEPARATE SENTENCE, not a reuse of `spoken(for:)`, and the difference is tense: this
    /// one says what a TAP will do. Collapsing the two into one string makes one of the two read
    /// wrong, which is the collapse #634b had to retract.
    func testTheLockButtonNamesWhoWouldGetTheClockBack() throws {
        XCTAssertTrue(TempoFollowLabel.unlockHint(for: Self.frame(.fallback))
                        .contains("simulated demo source"), """
            Unlocking under Simulation hands the clock back to the DEMO GENERATOR, and the \
            button still says it hands it to a body. This claim exists because 5b's first \
            wording read as a licence over exactly this control.
            """)
        XCTAssertTrue(TempoFollowLabel.unlockHint(for: Self.frame(.ble))
                        .contains("your body"), """
            The real-body hint lost the founder's phrase. It is TRUE with a strap on — only \
            the other two states move.
            """)
        XCTAssertFalse(TempoFollowLabel.unlockHint(for: nil).contains("your body"), """
            With no reading, unlocking hands the clock to nothing in particular. Naming a \
            body there invents the actor, which is this family's defect in its purest form.
            """)
        let code = try codeText(Self.field)
        // ⛔ TWO WRONG NEEDLES BEFORE THIS ONE, both caught by DRIVING the claim rather than
        // reading it. (1) A ban on the bare string was red on its own correct tree — the
        // sentence legitimately lives inside `unlockHint(for:)` now, so banning a string
        // convicts the definition that owns it. (2) The repair reached for `squeezed()` on a
        // needle CONTAINING a string literal, which strips the spaces INSIDE the literal and
        // forces a hand-squeezed "Tempolocked" that no reader can check against the source.
        // A POSITIVE needle avoids both: it names what must be there.
        XCTAssertTrue(squeezed(code).contains("TempoFollowLabel.unlockHint(for:bus.usableBio())"), """
            The lock button no longer asks `TempoFollowLabel.unlockHint(for:)`. Its sentence \
            then lives at the call site as a second definition of one decision (#416) and, on \
            the shipped tree, was the unconditional one — it said "your body" while unlocking \
            would hand the clock to the demo generator.
            """)
        let once = code.components(
            separatedBy: "\"Tempo locked — tap to let your body drive it again\"").count - 1
        XCTAssertEqual(once, 1, """
            The real-body unlock sentence is written \(once) times in code, not once. It \
            belongs to `unlockHint(for:)` alone.
            """)
    }

    // MARK: - helpers

    private struct FieldAnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    private static func frame(_ source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: 60, hrvNormalized: 0.4,
                       breathRate: 12, breathPhase: 0.25,
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
            throw FieldAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
