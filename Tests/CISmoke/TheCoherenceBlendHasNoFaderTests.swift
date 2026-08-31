// TheCoherenceBlendHasNoFaderTests.swift
// Echoel — a cross-fade with one end permanently selected, and a doc inviting a fader. #923.
//
// WHAT THIS RECORDS. `HRVCoherence.compute(rrMs:blend:)` cross-fades two independent spectral
// estimators — Welch at `blend` 0, Lomb–Scargle at 1. Measured 2026-08-31, both PRODUCTION call
// sites sit at **1.0**: `CameraRPPGBioPublisher` passes the literal `blend: 1.0`, and
// `PolarH10BioPublisher` passes `self.coherenceBlend`, a `public var … = 1.0` that **nothing
// under `Sources/` ever writes**. Its own doc says "a UI fader can bind this end-to-end" — a
// control that does not exist. Found by `scripts/doorless-state.py`, whose rule is the one this
// file applies: a tuning constant with no writer is fine, a knob whose doc names a user who
// cannot turn it is the defect.
//
// ⛔ THE OBVIOUS CONCLUSION IS AN OVER-CLAIM AND THIS FILE EXISTS PARTLY TO STOP IT. "Welch never
// reaches a shipped value" is FALSE. At b = 1.0 the mix is pure Lomb–Scargle, yes —
// `mix(w, l) = w·0 + l·1` — but one line earlier stands
// `guard welch.valid, lomb.valid else { return welch.valid ? welch : lomb }`, so a window where
// Lomb–Scargle comes back invalid and Welch does not is answered **by Welch, whole**. That is
// reachable by construction rather than by accident: both readings pass through
// `reading(from:)`, whose `guard total > 0, total.isFinite` is evaluated on DIFFERENT spectra of
// the same tachogram. ⚠️ Reachable-by-construction is NOT the same as demonstrated — no test
// here produces an RR series that diverges, and building one is its own slice. Stated so nobody
// promotes "possible" to "happens".
//
// ⚠️ AND THAT IS WHY THE COST IS RECORDED RATHER THAN REMOVED. Both spectra are computed on
// every window, on the bio path, and at the shipped blend one of them is discarded except in
// the fallback. Skipping Welch when `b == 1` looks like free performance and is NOT: it deletes
// the rescue above. If a later slice wants that win it has to decide what an invalid
// Lomb–Scargle should produce — a product/DSP question, not an optimisation.
//
// ⚠️ #364 — THIS FORBIDS NOTHING. Binding a fader, or hard-selecting one estimator, is
// legitimate work. When these claims go red for that reason the repair is to move the prose in
// `Bio/HRVCoherence.swift` and `Bio/PolarH10BioPublisher.swift` IN THE SAME COMMIT.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file COMPILES against the parent tree and every claim
// has a verdict there. **One is red on the parent** — the doc claim, because this commit is what
// rewrites the inviting sentence. The other five are counterweights (#343), green on both, and
// they are the value: they catch a tree that "tidies" the double computation away, that drops
// the fallback, or that removes the per-spectrum validity guard the fallback depends on.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheCoherenceBlendHasNoFaderTests: XCTestCase {

    private static let sourcesRoot = "Sources/Echoelmusic"
    private static let coherenceFile = "Sources/Echoelmusic/Bio/HRVCoherence.swift"
    private static let strapFile = "Sources/Echoelmusic/Bio/PolarH10BioPublisher.swift"
    private static let cameraFile = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"

    // MARK: - the measurement

    func testNothingUnderSourcesWritesTheBlend() throws {
        var writers: [String] = []
        let root = try repoRoot().appendingPathComponent(Self.sourcesRoot)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw XCTSkip("cannot enumerate \(Self.sourcesRoot) — refusing to report a green it did not earn")
        }
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            guard let text = try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            else { continue }
            for line in SourceText.codeOnly(text).split(separator: "\n", omittingEmptySubsequences: false) {
                guard line.contains("coherenceBlend") else { continue }
                // The declaration itself is the one legitimate assignment.
                if line.contains("var coherenceBlend") { continue }
                if line.contains("coherenceBlend =") || line.contains("coherenceBlend=") {
                    writers.append("\(relative): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertEqual(writers, [], """
            Something under Sources/ now writes `coherenceBlend`: \(writers). That is a real \
            fader arriving, not a defect. In the same commit, correct the doc on the property in \
            Bio/PolarH10BioPublisher.swift and the ⛔ note in Bio/HRVCoherence.swift — both \
            currently state that the shipped blend is permanently 1.0.
            """)
    }

    func testBothProductionCallSitesSitAtLombScargle() throws {
        let camera = SourceText.codeOnly(try rawText(Self.cameraFile))
        XCTAssertTrue(camera.contains("HRVCoherence.compute(rrMs: rrMs, blend: 1.0)"), """
            The camera path no longer computes coherence at blend 1.0. If it now uses a different \
            blend, the claim that BOTH shipped paths are pure Lomb–Scargle is stale — and that \
            claim is what the prose in Bio/HRVCoherence.swift rests on.
            """)
        let strap = SourceText.codeOnly(try rawText(Self.strapFile))
        XCTAssertTrue(strap.contains("blend: self.coherenceBlend"), """
            The strap path no longer feeds `coherenceBlend` into HRVCoherence.compute. That \
            property is then unused rather than merely unwritten, which is a different finding \
            and needs a different note.
            """)
    }

    // MARK: - counterweights: what a tidy-up would break

    func testBothSpectraAreStillComputedUnconditionally() throws {
        let code = SourceText.codeOnly(try rawText(Self.coherenceFile))
        XCTAssertTrue(code.contains("let welch = compute(rrMs: rrMs, method: .welch)"), """
            The Welch spectrum is no longer computed unconditionally in compute(rrMs:blend:). If \
            it was skipped at blend 1.0 as free performance, that ALSO deleted the fallback on \
            the next line, which is the only reason Welch is not inert today. See this file's \
            header: the win is real but it is not free, and choosing what an invalid \
            Lomb–Scargle should produce is a DSP decision, not a tidy-up.
            """)
    }

    func testTheWelchFallbackIsStillThere() throws {
        let code = SourceText.codeOnly(try rawText(Self.coherenceFile))
        XCTAssertTrue(code.contains("return welch.valid ? welch : lomb"), """
            The fallback that returns the Welch reading when Lomb–Scargle is invalid is gone. \
            That line is the whole reason "Welch never reaches a shipped value" is an OVER-claim \
            at blend 1.0. If it was removed deliberately, the header of this file and the note in \
            Bio/HRVCoherence.swift both have to say so in the same commit.
            """)
    }

    func testValidityIsStillDecidedPerSpectrum() throws {
        let code = SourceText.codeOnly(try rawText(Self.coherenceFile))
        XCTAssertTrue(code.contains("guard total > 0, total.isFinite else { return .invalid }"), """
            `reading(from:)` no longer rejects a spectrum with no total power. That guard is the \
            MECHANISM by which Welch and Lomb–Scargle can disagree about validity for the same \
            tachogram — remove it and the fallback above becomes unreachable, which would make \
            the double computation genuinely wasted rather than load-bearing.
            """)
    }

    func testTheBlendDocNoLongerPromisesAFaderThatExists() throws {
        let text = try rawText(Self.strapFile)
        XCTAssertFalse(text.contains("a UI fader can bind this end-to-end"), """
            The doc on `coherenceBlend` again invites a UI fader as though one were available. \
            Nothing under Sources/ writes the property, so a session reading that sentence plans \
            around a control it will not find — the doorless-state rule verbatim: a knob whose \
            doc names a user who cannot turn it is the defect.
            """)
    }

    // MARK: - helpers

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                \(relativePath) is not present — this guard inspects source text, so it SKIPS \
                rather than reporting a green it did not earn (#454)
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
