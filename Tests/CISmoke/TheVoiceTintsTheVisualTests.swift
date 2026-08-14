// TheVoiceTintsTheVisualTests.swift
// Echoel — #594 Voice→Color: the captured voice tints the visual palette.
//
// WHAT THIS GUARDS. The measured voice profile (64 max-normalized harmonic taps,
// #590) already carries two honest scalars: a spectral CENTROID (where the energy
// sits — warm/dark vs bright) and a ROUGHNESS (spectral irregularity). #594 distils
// them in ONE pure function (`VoiceTimbreProfiler.colorDescriptors`, DSP/,
// Foundation-only) and lets the Metal renderer bias its palette with them: centroid
// nudges `hueShift` (±0.05 max), roughness nudges saturation (×0.95…1.05). The bias
// is computed in `draw(in:)`'s MainActor block from `appliedVoiceProfile`
// (@ObservationIgnored — no SwiftUI subscription), CACHED behind a taps-equality
// gate, and is EXACTLY zero with no captured voice — the physical-colour default is
// byte-identical until a voice is live (brand law: the tone's physical colour stays
// the picture's identity; the voice is a tint, never a takeover).
//
// ⚠️ HONEST LIMITS. 5 tests, 23 `XCTAssert*` statements (hand-counted per test,
// 5+4+4+3+7; `XCTUnwrap` census: two in test 1, one in test 2, one in test 4, and
// one `XCTFail` guard-else in test 2 — all outside the count). Tests 1–4 are END-TO-END BEHAVIOUR on the shipped pure
// static; test 5 is SOURCE-TEXT JOINS (the renderer is a Metal delegate no test
// host can drive). What no test here can prove: that the tint LOOKS right — the
// ±magnitudes are taste, founder-tunable — and that the draw-path read costs
// nothing at 60 fps. Registered gap, deliberate: the EXTERNAL DISPLAY draws
// untinted (`ExternalDisplayScene` injects no synth; the optional environment
// read is what keeps that scene from crashing — wiring the synth through the
// bridge is its own slice). Device probe (NEEDS-FOUNDER-VERIFY: capture a dark
// hum vs a bright "eee", open the visual — the palette should lean warm vs cool;
// Clear → the default look returns exactly).
//
// ⭐ GRADING (§3). Transcribed in Python (SourceText.codeOnly re-implemented;
// every needle raw vs stripped; all four E2E tests hand-driven numerically —
// warm 0.123 / bright 0.906 / flat 0 / smooth 0.119 / comb 0.969 / holes finite).
// Against the parent all joins are ONE absence reported once (#486) and FORWARD
// (#433) — this commit creates the function and every anchor. Stripper: TRAGEND
// (1 of 7 join verdicts flipped) — the updateUIView-law counterweight is PROSE,
// which `codeOnly` blanks by design; the transcription caught it before the file
// ever ran, and that one needle now reads the RAW source, stated inline.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVoiceTintsTheVisualTests: XCTestCase {

    // MARK: - 1–4. The pure decision (END-TO-END)

    /// The core ordering: a fundamental-heavy (warm) voice sits LOW, a voice with
    /// its energy in high harmonics sits HIGH, and both live in [0, 1].
    func testAWarmVoiceSitsLowAndABrightVoiceSitsHigh() throws {
        var warm = [Float](repeating: 0, count: 32)
        warm[0] = 1; warm[1] = 0.4; warm[2] = 0.15; warm[3] = 0.05
        var bright = [Float](repeating: 0.02, count: 32)
        bright[20] = 0.8; bright[24] = 1; bright[28] = 0.7
        let w = try XCTUnwrap(VoiceTimbreProfiler.colorDescriptors(taps: warm))
        let b = try XCTUnwrap(VoiceTimbreProfiler.colorDescriptors(taps: bright))
        XCTAssertLessThan(w.centroid, 0.35, "energy at the fundamental = warm/dark = low")
        XCTAssertGreaterThan(b.centroid, 0.6, "energy in high harmonics = bright = high")
        XCTAssertLessThan(w.centroid, b.centroid, "the ordering IS the feature")
        XCTAssertTrue((0...1).contains(w.centroid) && (0...1).contains(w.roughness))
        XCTAssertTrue((0...1).contains(b.centroid) && (0...1).contains(b.roughness))
    }

    /// Roughness orders spectra by irregularity: a flat envelope is 0, a smooth
    /// decay is small, an alternating comb is near the top.
    func testRoughnessOrdersSmoothBelowJagged() throws {
        let flat = [Float](repeating: 0.5, count: 32)
        let smooth = (0..<32).map { Float(1.0 / Double($0 + 1)) }
        let comb = (0..<32).map { Float($0 % 2 == 0 ? 1 : 0) }
        let f = try XCTUnwrap(VoiceTimbreProfiler.colorDescriptors(taps: flat))
        XCTAssertEqual(f.roughness, 0, accuracy: 1e-9, "a flat envelope has zero irregularity")
        guard let s = VoiceTimbreProfiler.colorDescriptors(taps: smooth),
              let c = VoiceTimbreProfiler.colorDescriptors(taps: comb) else {
            return XCTFail("finite non-empty spectra must yield descriptors")
        }
        XCTAssertLessThan(s.roughness, c.roughness, "smooth decay < alternating comb")
        XCTAssertGreaterThan(c.roughness, 0.8, "the comb is the roughest shape this measure knows")
        XCTAssertLessThan(s.roughness, 0.3, "a 1/k decay reads as smooth")
    }

    /// Degenerate profiles REFUSE rather than guessing: empty, single-tap,
    /// all-zero and all-NaN each return nil — the renderer then keeps the
    /// untinted default instead of painting from garbage.
    func testDegenerateProfilesRefuse() {
        XCTAssertNil(VoiceTimbreProfiler.colorDescriptors(taps: []))
        XCTAssertNil(VoiceTimbreProfiler.colorDescriptors(taps: [1]))
        XCTAssertNil(VoiceTimbreProfiler.colorDescriptors(taps: [Float](repeating: 0, count: 32)))
        XCTAssertNil(VoiceTimbreProfiler.colorDescriptors(
            taps: [Float](repeating: .nan, count: 32)))
    }

    /// Non-finite and negative taps are sanitized, not propagated: a profile with
    /// NaN holes still yields finite, clamped descriptors (edge-case law — a NaN
    /// at any DSP boundary is an input, not an impossibility).
    func testNaNHolesAreSanitizedNotPropagated() throws {
        var taps = [Float](repeating: 0.4, count: 32)
        taps[3] = .nan; taps[7] = -1; taps[11] = .infinity
        let d = try XCTUnwrap(VoiceTimbreProfiler.colorDescriptors(taps: taps))
        XCTAssertTrue(d.centroid.isFinite && d.roughness.isFinite)
        XCTAssertTrue((0...1).contains(d.centroid))
        XCTAssertTrue((0...1).contains(d.roughness))
    }

    // MARK: - 5. The wiring joins (SOURCE-TEXT)

    /// The renderer reads the profile in draw's MainActor block, caches behind a
    /// taps-equality gate, applies the bias at the ONE update call — and the
    /// updateUIView no-live-read law survives untouched.
    func testTheTintIsWiredInTheDrawPathOnly() throws {
        let view = try source("Sources/Echoelmusic/Views/MetalBioView.swift")
        XCTAssertEqual(codeOccurrences(
            of: "@Environment(PolySynthVoice.self) private var synth: PolySynthVoice?", in: view), 1,
            "the view forwards the synth REFERENCE like bus/governor — the profile "
            + "itself is read in draw, off the SwiftUI graph. The OPTIONAL form is "
            + "load-bearing: ExternalDisplayScene mounts this view WITHOUT the synth "
            + "in its environment (only bus/governor/recorder), so the non-optional "
            + "spelling crashes the beamer scene at view creation")
        XCTAssertEqual(codeOccurrences(of: "c.synth = synth", in: view), 1)
        XCTAssertEqual(codeOccurrences(of: "if taps != lastVoiceTaps", in: view), 1,
                       "the descriptors are recomputed ONLY when the profile changes "
                       + "(capture/recall/clear) — never per frame at 60 fps")
        XCTAssertEqual(codeOccurrences(of: "hueShift: lookHue + voiceHueBias", in: view), 1,
                       "centroid reaches the REAL palette input — vp.hue is consumed "
                       + "by no renderer path (only vp.pulseHz is), so biasing "
                       + "BioVisualParams would have been wired-but-dead")
        XCTAssertEqual(codeOccurrences(
            of: "saturation: lookSaturation * voiceSatFactor", in: view), 1)
        // RAW read on purpose: this needle IS prose (the updateUIView law comment),
        // so `codeOnly` blanks it by design — the transcription pass caught exactly
        // that (stripped=0, raw=1) before this file ever ran. A living law comment
        // is not a retracted claim, so scanning for it is #491-safe.
        XCTAssertEqual(codeOccurrences(
            of: "do NOT read the live bus / governor",
            in: try rawSource("Sources/Echoelmusic/Views/MetalBioView.swift")), 1,
            "COUNTERWEIGHT: the updateUIView law survives — forwarding "
            + "references is its sanctioned form, and this slice adds no "
            + "live read there")
        let profiler = try source("Sources/Echoelmusic/DSP/VoiceTimbreProfiler.swift")
        XCTAssertEqual(codeOccurrences(
            of: "public static func colorDescriptors(taps: [Float]) -> (centroid: Double, roughness: Double)?",
            in: profiler), 1,
            "the ONE pure definition, in DSP/ (Foundation-only law holds — no "
            + "Core/Sequencer type enters this file with it)")
    }

    // MARK: - helpers (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct TintAnchorMissing: Error { let reason: String }

    private func codeOccurrences(of needle: String, in stripped: String) -> Int {
        stripped.components(separatedBy: needle).count - 1
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw TintAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// UNSTRIPPED variant for the one prose-law needle above — everything else in
    /// this file goes through `codeOnly`.
    private func rawSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw TintAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }
}
