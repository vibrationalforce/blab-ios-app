// TheBreathGateSaysWhyItIsClosedTests.swift
// Echoel — #567, cycle C3 of the 2026-08-13 handover ("respiration diagnostics, NOT
// construction").
//
// THE SITUATION, stated once. Respiration is not missing — `CameraRPPGBioPublisher` computes it
// and publishes `breathRate`/`breathPhase` behind `resp.confidence >= 0.4 && resp.ratePerMinute
// > 0`. In the 2026-08-12 device log that gate never opened while signal quality was nominally
// high. The estimator is STARVED, not absent, and C3's instruction is therefore to instrument
// before touching anything: "changing a threshold blind is how the 2026-08-12 confusion
// happened."
//
// ⭐ WHAT THIS CYCLE ACTUALLY ADDS, and why it is not just a print. `confidence` is a PRODUCT —
// an envelope term times a cycle-count term that the envelope also vetoes — so one low number
// has two causes with two different fixes: a dead envelope (no respiratory swing reached the
// sensor: exposure drift, contact — C3b candidates a and b) or a healthy envelope with too few
// crossings (the swing is there, no period measured — candidate c, the 0.4 gate itself). The log
// could not tell them apart, and C3b has to choose ONE candidate on that evidence. So
// `RespirationEstimator` grew `lastEnvConf`, a write-only diagnostic mirror of the numerator,
// and the breadcrumb prints it beside the product. A ratio published without its numerator
// makes the next decision a guess.
//
// ⚠️ THE LIMIT, PER ASSERTION:
//   · claims 1–2 are END-TO-END BEHAVIOUR over `RespirationEstimator`, a pure Foundation-only
//     value type driven exactly as its existing guards drive it (`ingest(heartRate:at:)`).
//   · claims 3–4 are SOURCE SCANS. The publisher is `@MainActor` and owns a live capture
//     session; no test here can run its loop, so the gate expression and the breadcrumb are
//     pinned as text. Claim 3 is the more important of the two: it makes C3's PROMISE — no
//     behaviour change, no threshold change — executable rather than a sentence in a commit.
//   · DEVICE PROBE, open and the whole point of the cycle: two founder sessions, one breathing
//     deliberately slowly (~6/min) and one normally, with the new `breath:` lines present.
//     Nothing here can produce that evidence; this file only guarantees the instrument is real.
//
// ⚠️ HONEST GRADING, transcribed in Python against the parent (`e2ea9ae`) and this tree. The
// file does NOT compile against the parent — `lastEnvConf` does not exist there and claims 1–2
// name it — so per §3 no assertion has a verdict there; the grading is hand-transcribed logic:
//   · ONE ABSENCE, REPORTED ONCE (#486): the missing mirror is a single fact, not two findings.
//   · claim 1 is a FORWARD guard over the property this commit creates.
//   · claim 2 is a COUNTERWEIGHT and the one that matters most: it pins the estimator's OWN
//     stated invariant (`confidence <= envConf`), so if the mirror is ever wired backwards —
//     assigned after a later mutation, or from a different term — the two numbers separate and
//     this says so. A diagnostic that lies is worse than none, because C3b will act on it.
//   · claim 3 is a COUNTERWEIGHT green on BOTH trees. That is the point: this cycle changed
//     NOTHING about the gate, and the assertion is what proves it rather than the commit
//     message claiming it.
//   · claim 4 is a FORWARD guard over text this commit writes.
//   · STRIPPER: PROPHYLAKTISCH, 0 of 4 verdicts flip — measured on both trees. Claim 3's needle
//     appears only in code; claim 4's five field names appear only inside the breadcrumb
//     literal. It is kept because the surrounding block DISCUSSES the gate at length, and the
//     day someone quotes `resp.confidence >= 0.4` in an explanatory comment the raw scan would
//     start passing on prose.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBreathGateSaysWhyItIsClosedTests: XCTestCase {

    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    /// A heart rate with a respiratory sinus arrhythmia riding on it — the signal the estimator
    /// is built to read. 6 breaths/min is the resonance rate the founder will be breathing at in
    /// the device session this cycle exists to capture, so the fixture and the probe agree.
    private func breathe(_ est: inout RespirationEstimator,
                         seconds: Double, swingBPM: Double, breathsPerMinute: Double = 6) {
        let base = 66.0
        var t = 0.0
        while t < seconds {
            let phase = 2 * Double.pi * (breathsPerMinute / 60) * t
            let hr = base + swingBPM * sin(phase)
            est.ingest(heartRate: hr, at: t)
            t += 60.0 / base                       // one sample per beat, as the analyzer feeds it
        }
    }

    // MARK: - claim 1 (END-TO-END) — the numerator is actually published

    func testTheEnvelopeMirrorIsWrittenAndBounded() {
        var est = RespirationEstimator()
        XCTAssertEqual(est.lastEnvConf, 0, accuracy: 1e-12, """
            A fresh estimator already reports an envelope. The mirror must start at zero or a \
            log line taken before any breath was seen would assert a swing that was never \
            measured — which is precisely the class of false reassurance C3 exists to remove.
            """)
        breathe(&est, seconds: 90, swingBPM: 3.0)
        XCTAssertGreaterThan(est.lastEnvConf, 0, """
            A 90-second take with a 3 bpm respiratory swing left the envelope mirror at zero. \
            Either nothing writes it, or it is written before the term it mirrors is computed — \
            both make every `envConf=` in a device log a constant, and C3b would then pick its \
            candidate from a number that cannot move.
            """)
        XCTAssertLessThanOrEqual(est.lastEnvConf, 1, """
            The mirror exceeded 1. It mirrors `Swift.min(1.0, e / 1.5)`, so a value above 1 \
            means it is being assigned from the raw envelope instead of the clamped term — the \
            log would then read as high confidence exactly where the signal is most extreme.
            """)
    }

    // MARK: - claim 2 (COUNTERWEIGHT, END-TO-END) — and it agrees with what it explains

    /// The estimator states its own invariant in source: `confidence <= envConf * freshness`.
    /// Since both freshness and the count term are at most 1, `confidence <= lastEnvConf` must
    /// hold at every moment — and if it ever does not, the mirror is not mirroring the term the
    /// comment says it does. A diagnostic that disagrees with the value it explains sends the
    /// next cycle to the wrong candidate, which is worse than shipping no diagnostic at all.
    func testTheMirrorNeverContradictsTheConfidenceItExplains() {
        for swing in [0.0, 0.4, 1.5, 4.0] {
            var est = RespirationEstimator()
            breathe(&est, seconds: 120, swingBPM: swing)
            XCTAssertLessThanOrEqual(est.confidence, est.lastEnvConf + 1e-9, """
                At a \(swing) bpm swing the estimator reports confidence \(est.confidence) with \
                an envelope term of \(est.lastEnvConf). The envelope VETOES the count — the \
                file states `confidence <= envConf * freshness` as its invariant — so \
                confidence above the envelope means the mirror is stale, assigned from a \
                different expression, or written before the value it claims to carry.
                """)
            XCTAssertGreaterThanOrEqual(est.confidence, 0)
        }
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — C3 promised to change nothing, and here is the proof

    /// The gate the whole cycle is ABOUT, pinned unchanged. C3's own instruction is "NO
    /// behaviour change, NO threshold change in this cycle", and a promise in a commit message
    /// is not checkable six weeks later. When C3b deliberately moves this — candidate (c) is
    /// exactly "the 0.4 confidence gate itself" — this goes red and its message says so, which
    /// is the difference between a guard that blocks work (#364) and one that dates it.
    func testThePublishGateIsUnchangedByThisCycle() throws {
        let code = try publisherCode()
        XCTAssertTrue(code.contains("resp.confidence >= 0.4 && resp.ratePerMinute > 0"), """
            The breath publish gate is no longer `resp.confidence >= 0.4 && \
            resp.ratePerMinute > 0`. If this is C3b candidate (c) — moving the 0.4 threshold — \
            that is legitimate work and this assertion moves WITH it, in the same commit, \
            carrying the device evidence that justified the new number. If it is not, a \
            diagnostics-only cycle changed behaviour, which is the one thing C3 forbade.
            """)
        XCTAssertTrue(code.contains("breathRate: measuredBreath ? Float(resp.ratePerMinute) : 0"), """
            The published breath rate no longer passes through `measuredBreath`. A rate of zero \
            is not a measurement — the comment above the gate records what publishing an \
            unmeasured `resp.amplitude` as `breathPhase` cost once already.
            """)
    }

    // MARK: - claim 4 — the instrument names every field C3b needs

    /// A breadcrumb missing one field is a session the founder has to repeat. The five names are
    /// asserted individually so a failure says WHICH one went, not that "the line changed".
    func testTheBreadcrumbCarriesEveryDiscriminator() throws {
        let code = try publisherCode()
        XCTAssertTrue(code.contains("\"breath: rate="), """
            The `breath:` breadcrumb is gone. Without it C3b has three candidates and no \
            evidence, which is the state C3 was created to end.
            """)
        for field in ["amp=", "envConf=", "conf=", "gate="] {
            XCTAssertTrue(code.contains(field), """
                The breath breadcrumb no longer carries `\(field)`. Each field discriminates a \
                different C3b candidate: `envConf` separates a dead envelope (exposure/contact) \
                from a missing period, `amp` catches the motion-artifact spikes that correlate \
                with collapsing autocorrelation, `conf` and `gate` say whether the published \
                gate agreed. Dropping one costs a founder device session, not a line of text.
                """)
        }
    }

    // MARK: - source access

    private struct BreathAnchorMissing: Error { let reason: String }

    private func publisherCode() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(Self.publisher)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BreathAnchorMissing(reason: """
                \(Self.publisher) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
