// ThePeerSeesWhetherItIsABodyTests.swift
// Echoel — #629: a peer's row must say whether those numbers came from a body or from the
// Demo source. Registered by #627b as the last unclosed half of the source-honesty law.
//
// WHAT THIS GUARDS. `BioEgressPolicy` admits `.fallback` (Echoel synthesises it itself, so
// 5.1.3 — which is about data read out of HealthKit — does not touch it), and `BioPeek`
// carried NO source field. In a Live Colabo session another performer therefore saw your
// simulator's BPM and coherence under your peer name, styled exactly like a measurement,
// with nothing on the wire that could have told them otherwise. #627 marked the two
// on-device surfaces and #627b marked the sheet they open; this is the surface someone ELSE
// looks at, and it is the only one where the viewer cannot check the source for themselves.
//
// THE SHAPE OF THE FIX, and why not the other one. Blocking `.fallback` from egress would
// blank the peer's row — and `BioPeek`'s own doc already settled that trade for the
// non-finite case: a blank row ASSERTS the network stopped, "the worse of the two lies".
// Rehearsing or teaching with the simulator is a real use. So: mark it, do not silence it.
//
// `synthetic` is OPTIONAL and that is load-bearing. `nil` = the sender did not say (an older
// build). It must render like `false` — unmarked — and must NEVER be read as "real": turning
// a silent sender into a claim is the same over-claim this field exists to end, only dressed
// as a default. Claim 4 pins the decode, claim 5 pins the init default.
//
// KIND (§1): claims 1-6 and 8 are BEHAVIOURAL against the real `BioPeek` — the projection,
// the wire round-trip, forward compatibility and the size budget are all executable here,
// so almost nothing in this file is a text scan. Claim 7 is a SOURCE SCAN of five needles in
// the view — two call sites, the VoiceOver ternary, the chip and the heart tint — because a
// SwiftUI row cannot be driven in this bundle. (#629b: it said "the two view call sites"
// while carrying three needles, and then grew to five.)
//
// GRADING (#433 / §3, against `509e864`) — and the parent's failure MODE is stated, because
// "red on the parent" hides two different things here:
//   · claims 1-5 name `BioPeek.synthetic`, which does not exist on the parent, so the whole
//     bundle FAILS TO COMPILE there. They are regressions in the sense that matters (the
//     capability is absent), but nobody would ever see them fail as assertions. Recorded
//     this way rather than as a flat "red", which would suggest a running test.
//   · claim 7 is a REGRESSION, HAND-TRANSCRIBED: on `509e864` its needles are 0 / 0 / 0 and
//     on the worktree 1 / 1 / 1, raw and stripped alike. ⛔ #629b: this line said it "WOULD
//     have run and failed" — it would not have RUN at all, because the bundle it lives in
//     does not compile against that parent. The measurement was right and the verb was
//     wrong.
//   · claim 5 additionally records a CHOICE rather than a defect: `nil` over `false` as the
//     memberwise default. There was no parameter to get wrong; there is now, and the wrong
//     value would be the convenient one.
//   · claims 6 and 8 are COUNTERWEIGHTS. ⛔ #629b: "they compile and pass on both trees" was
//     self-contradictory two bullets after stating that the bundle does not compile against
//     the parent — NO assertion in this file has a verdict there, and §3 forbids letting
//     "not gradable against the parent" read as "green against its own tree" (#488 shipped a
//     red gate for a cycle behind that exact ambiguity). What is true: their SUBJECTS are
//     unchanged by this commit, hand-transcribed. 6 is the important one: the cheap way to stop the lie is to add `.fallback` to the deny list,
//     which trades a marked demo for a blanked row and confuses provenance with privacy. 8
//     keeps the added field from quietly blowing the streaming size budget.
//
// Stripper: not needed for claims 1-6 and 8 (behavioural). Claim 7 delegates to
// `SourceText.codeOnly` (#453) and is MEASURED PROPHYLAKTISCH — no comment on either tree
// spells `synthetic: live?.synthetic` or `synthetic: f?.source == .fallback` in code form.
//
// ⚠️ #364: marking by a DIFFERENT mechanism is not forbidden — a `source` string on the wire
// would carry more and is a bigger decision (it would also have to answer what a receiver
// may do with "Health", which cannot egress at all). What is forbidden silently is going
// back to a payload that cannot distinguish a body from a simulation.

import Foundation
import XCTest
@testable import Echoelmusic

final class ThePeerSeesWhetherItIsABodyTests: XCTestCase {

    private func frame(_ source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: CFAbsoluteTimeGetCurrent(),
                       heartRateBPM: 64, hrvNormalized: 0.44,
                       breathRate: 6, breathPhase: 0.5,
                       coherence: 0.61, motionEnergy: 0, source: source)
    }

    /// 1 — REGRESSION: the Demo source is declared on the wire.
    func testASyntheticFrameTravelsMarked() {
        let peek = BioPeek.egressible(from: frame(.fallback))
        XCTAssertNotNil(peek, """
            the demo no longer egresses at all. That is not the fix — it blanks the peer's \
            row, which asserts the network stopped; `BioPeek`'s own doc calls that the worse \
            of the two lies. Mark the demo, do not silence it (#629).
            """)
        XCTAssertEqual(peek?.synthetic, true, """
            a `.fallback` frame reaches a peer without saying so. The receiver has no other \
            way to know — `BioPeek` carries no source — so an unmarked demo is indistinguishable \
            from your heart on their screen (#629).
            """)
    }

    /// 2 — REGRESSION: a measured body says so POSITIVELY, so the marker's absence is a
    /// statement and not merely a silence.
    func testAMeasuredFrameTravelsMarkedAsMeasured() {
        for source in [BioSource.cameraPPG, .ble, .faceCam] {
            // #629b: unwrap FIRST. Without it, a source that stopped egressing at all fails
            // here with a message about marking, i.e. names the wrong defect; claim 6 would
            // catch the real cause but only after this one has misdirected the reader.
            guard let peek = try? XCTUnwrap(BioPeek.egressible(from: frame(source)),
                                            "\(source) no longer egresses at all — that is "
                                            + "claim 6's subject, not this one") else { continue }
            XCTAssertEqual(peek.synthetic, false, """
                \(source) egresses with `synthetic` not equal to false. A build that KNOWS \
                must say so; leaving it nil would make a real reading indistinguishable from \
                an older sender that cannot answer (#629).
                """)
        }
    }

    /// 3 — REGRESSION: the field survives the wire, which is the only thing that matters —
    /// it is set on one phone and read on another.
    func testTheMarkerSurvivesTheWire() {
        let peek = BioPeek.egressible(from: frame(.fallback))
        let payload = ColabPayload(kind: "bio", senderName: "Stage iPhone", bio: peek)
        guard let data = payload.encoded() else { return XCTFail("encode failed") }
        XCTAssertEqual(ColabPayload.decode(data)?.bio?.synthetic, true, """
            the marker is lost in encode/decode. It is set on the SENDER and read on the \
            RECEIVER; a field that does not cross the wire marks nothing at all (#629).
            """)
    }

    /// 4 — REGRESSION: an older sender's payload has no such key, and that must decode as
    /// "did not say" rather than failing or defaulting to a claim.
    func testAnOlderSendersPayloadDecodesAsUnknown() {
        let legacy = Data(#"{"kind":"bio","senderName":"Old","bio":{"bpm":72,"coherence":0.6,"hrvNormalized":0.4,"breathRate":5.5}}"#.utf8)
        let back = ColabPayload.decode(legacy)
        XCTAssertNotNil(back?.bio, """
            a payload from a build without `synthetic` no longer decodes. This file's header \
            promises forward compatibility through optional fields; a required field breaks \
            every peer running an older build (#629).
            """)
        XCTAssertNil(back?.bio?.synthetic, """
            a missing key decodes as a VALUE. Silence from a sender that cannot answer must \
            stay silence — reading it as `false` would print a measured body from a build \
            that never said one (#629).
            """)
    }

    /// 5 — REGRESSION (in form) / the recorded CHOICE (in substance): a hand-built peek says
    /// "unknown", never "real". `BioPeek` is `public` with a memberwise init, which is the
    /// hole `egressible` exists to narrow; the default must not fill it with a claim.
    func testAHandBuiltPeekClaimsNothing() {
        let peek = BioPeek(bpm: 60, coherence: 0.5, hrvNormalized: 0.5, breathRate: 6)
        XCTAssertNil(peek.synthetic, """
            the memberwise init now defaults `synthetic`. Whatever it defaults TO is a claim \
            this initialiser cannot support — it never saw a `BioSampleFrame`. `nil` is the \
            only honest default (#629).
            """)
    }

    /// 6 — COUNTERWEIGHT: the egress RULE is untouched. The cheap "fix" is to deny
    /// `.fallback`; that blanks the row and confuses a provenance question with a privacy
    /// one. This nails it shut in both directions.
    func testTheEgressRuleItselfDidNotMove() {
        for source in [BioSource.healthKit, .watch, .oura] {
            XCTAssertNil(BioPeek.egressible(from: frame(source)), """
                \(source) now egresses. That is the App Store 5.1.3 rule, not the marking \
                question — data read out of the HealthKit store must not leave the device, \
                and no amount of labelling makes it allowed (#629).
                """)
        }
        for source in [BioSource.cameraPPG, .ble, .faceCam, .fallback] {
            XCTAssertNotNil(BioPeek.egressible(from: frame(source)), """
                \(source) stopped egressing. #629 adds a LABEL; it must not narrow who may \
                share. Blocking the demo in particular trades a marked row for a blank one.
                """)
        }
    }

    /// 7 — REGRESSION (source scan): both rows pass it, VoiceOver leads with it, and — since
    /// #629b — the two things a viewer actually SEES are pinned as well.
    func testBothRowsPassTheMarkerAndVoiceOverLeadsWithIt() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Echoelmusic/Studio/LiveColaboView.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        let lines = SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // ⛔ #678: respelled by #677 (`== .fallback` → `.isSynthetic == true`).
        XCTAssertEqual(lines.filter { $0.contains("synthetic: f?.source.isSynthetic == true") }.count, 1, """
            your OWN row no longer marks the demo. It reads the frame directly — no wire, no \
            optionality — so this is the one row that can always answer (#629).
            """)
        XCTAssertEqual(lines.filter { $0.contains("synthetic: live?.synthetic") }.count, 1, """
            the PEER rows no longer pass the marker through. The field then crosses the wire \
            and is dropped one line before it would have been shown (#629).
            """)
        XCTAssertEqual(lines.filter {
            $0.contains("synthetic == true ? \"Simulated demo, \" : \"\"")
        }.count, 1, """
            VoiceOver no longer LEADS with the marker. A trailing "simulated" is heard as a \
            measurement with an addendum — the same ordering law the header pill's \
            `accessibilityText` follows (#627/#629).
            """)
        // ⛔ #629b: the two assertions below were MISSING, and they cover the slice's own
        // headline. Deleting the whole `if synthetic == true { Text("Demo") … }` block, or
        // reverting the heart tint to a bare `highlight ?`, left all eight claims green —
        // the VISIBLE marker was unguarded while the VoiceOver string was pinned. #627 pins
        // its equivalent accent as a literal and #627b had to add a colour claim for exactly
        // this reason; #629 reproduced both holes one surface over.
        //
        // GRADED AND MEASURED against `963f9f6` (#629 itself), not averaged: the chip needle
        // is a COUNTERWEIGHT (1 on both trees — the chip existed, only the guard did not),
        // the tint needle is a REGRESSION (0 → 1, because #629's expression lacked the
        // `bpm > 0` term that makes its own comment true). Both 0 on `509e864`. Raw ==
        // stripped on all three trees, so the stripper stays PROPHYLAKTISCH.
        XCTAssertEqual(lines.filter { $0.contains("if synthetic == true {") }.count, 1, """
            the visible "Demo" chip is gone from `bioLine`. VoiceOver would still say it and \
            every other claim in this file would still pass — a marker only a screen reader \
            can perceive is not the marker this slice shipped (#629b).
            """)
        XCTAssertEqual(lines.filter {
            $0.contains("(highlight && synthetic != true && bpm > 0)")
        }.count, 1, """
            the heart tint no longer gates on realness. The accent is the "a real pulse is \
            here" colour — the same claim the header pill makes with `(locked && !synthetic)` \
            — so a demo row painting it says with colour what the row denies in words. The \
            `bpm > 0` term is what makes that claim TRUE here rather than merely asserted \
            (#629b).
            """)
    }

    /// 8 — COUNTERWEIGHT: the payload streams at `PeerReading.sendInterval`, so the size
    /// budget the existing round-trip test defends still holds with the field set.
    func testTheMarkedPayloadIsStillTiny() {
        let peek = BioPeek.egressible(from: frame(.fallback))
        let data = ColabPayload(kind: "bio",
                                senderName: String(repeating: "N", count: 63),
                                bio: peek).encoded()
        XCTAssertNotNil(data)
        XCTAssertLessThan(data?.count ?? .max, 512, """
            the bio payload outgrew its budget. It streams every \
            \(PeerReading.sendInterval) s over an unreliable transport; a fat frame is a \
            dropped frame, and a dropped frame blanks someone's row.
            """)
    }
}
