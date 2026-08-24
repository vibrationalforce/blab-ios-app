// TheComposerWritesPerNoteVelocityTests.swift
// Echoel — #779. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROTECTS, AND WHY IT IS AN *UNDER*-CLAIM GUARD. `docs/architecture.html`'s
// BioComposer row said "Per-note velocity, automation and richer voice-leading are ROADMAP".
// One of those three shipped. Measured end to end on the path a user actually takes:
//
//   BioComposer  → `hVel(...)` jitters every written note by ±0.05, `metricAccent(step:)`
//                  returns 1.0 / 0.95 / 0.92 / 0.86 by metric position, `padVelocity` and
//                  `subVel` follow breath depth, `bassVelocity` is lifted off the pad and
//                  `pulseVel` is 0.45× it — five independent sources of variation.
//   Note         → `velocity: Float`, clamped 0…1, `Codable`, persisted.
//   Export       → `EchoelStudioView` calls `MIDIFileExporter.exportCombined(notes:…)`, which
//                  calls `melodyEvents`, which writes `Int(n.velocity * 127 * velScale)` as the
//                  note-on velocity byte. Nothing flattens it in between.
//
// ⚠️ THE OTHER TWO THIRDS ARE CORRECTLY ROADMAP AND MUST STAY SO. `AutomationPlayer` has no
// production writer (the surface that would draw a curve went with #121 Slice 4), and
// "richer voice-leading" is a judgement, not a flag. The repair therefore SPLITS the sentence
// rather than flipping it — this guard bans the velocity third from the roadmap list, and says
// nothing about the other two, so wiring automation later needs no change here (#364).
//
// ⚠️ WHY A SEPARATE FILE RATHER THAN A CLAIM IN `TheDynamicsAreThePersonsTests`. That file owns
// the performer-FINGERPRINT reasoning (how far the bass is lifted over the pad, and the honest
// limit that ±0.07 is a bias across takes, not a per-take guarantee). This is a different
// decision — whether per-note velocity exists at all and survives to the file — and #416 wants
// one home per decision, not one file per topic. Neither file restates the other.
//
// ⛔ THE SWEEP THAT SHOULD HAVE FOUND THIS RAN FOUR CYCLES EARLIER AND LOOKED THE OTHER WAY.
// #765–#775 built needle after needle for things-not-to-promise; #775 finally recorded that
// "a truth sweep that only looks for over-claims finds half the defects" and fixed ten
// under-claims about MPE out. It fixed the ones about MPE. The roadmap-side sweep that found
// THIS one read ~100 "roadmap/planned" sentences across `docs/` and turned up exactly one more
// defect — every other claim measured honest (LinkKit 0 files, HomeKit 0, CoreML 0, Syphon 0,
// Atmos 0; `LoopExporter` really does hard-set `.wav`; `MIDIOutput` really does send MIDI 1.0
// bytes; no modelled analog compressor exists). **A one-in-a-hundred hit rate is the point:**
// the sweep is cheap and the single hit was on the page a DAW user reads before deciding
// whether the export is worth opening.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheComposerWritesPerNoteVelocityTests: XCTestCase {

    private static let architecture = "docs/architecture.html"

    // MARK: - claim 1 — the composer's metric hierarchy really varies

    /// The cheapest of the five sources, and the only one that is a pure function of the step,
    /// so it can be asserted without building a take. If this flattens to a constant, the
    /// chops go back to reading as mechanical ("unprofessionell", the founder's word) and the
    /// page's new LIVE tag is over-claiming by one source.
    func testTheMetricAccentIsNotFlat() {
        let bar = (0..<16).map { BioComposer.metricAccent(step: $0) }
        XCTAssertEqual(Set(bar).count, 4, """
            `BioComposer.metricAccent(step:)` no longer returns four distinct weights over a \
            bar — it returned \(Set(bar).sorted()).

            The downbeat/beat-3/backbeat/offbeat hierarchy is one of the five things that make \
            `docs/architecture.html` say per-note velocity is LIVE. If it was deliberately \
            flattened, that sentence moves in the same commit (#456).
            """)
        XCTAssertGreaterThan(bar[0], bar[1],
                             "The downbeat must still be louder than the step after it.")
        XCTAssertGreaterThan(bar[8], bar[1],
                             "Beat 3 must still be louder than an offbeat.")
    }

    // MARK: - claim 2 — the value survives into the exported .mid bytes

    /// BEHAVIOURAL, through the same entry point `EchoelStudioView` calls. `.tight` is
    /// zero-jitter (`timingTicks: 0, velocityJitter: 0`), so `velScale` is exactly 1 and the
    /// expected bytes are arithmetic, not a golden blob: `Int(0.25 * 127) = 31` and
    /// `Int(0.95 * 127) = 120`.
    ///
    /// ⚠️ It scans for `0x90` because the serializer writes a status byte per event and uses no
    /// running status. A VLQ delta byte could in principle collide, so the assertion is
    /// "the expected velocity is AMONG the bytes found for this pitch", never "exactly one
    /// match" — a stricter form would fail for a reason that has nothing to do with velocity.
    func testTheExportedFileCarriesEachNotesOwnVelocity() {
        let notes = [Note(pitch: 60, startTick: 0, lengthTicks: 480, velocity: 0.25),
                     Note(pitch: 67, startTick: 960, lengthTicks: 480, velocity: 0.95)]
        let data = MIDIFileExporter.exportCombined(notes: notes, steps: [], accents: [],
                                                   tempo: 120, bars: 1)
        let bytes = [UInt8](data)
        func velocities(forPitch pitch: UInt8) -> [UInt8] {
            guard bytes.count >= 3 else { return [] }
            return (0...(bytes.count - 3)).compactMap {
                bytes[$0] == 0x90 && bytes[$0 + 1] == pitch ? bytes[$0 + 2] : nil
            }
        }
        let soft = velocities(forPitch: 60)
        let loud = velocities(forPitch: 67)
        XCTAssertTrue(soft.contains(31), """
            The exported .mid does not carry note 60's own velocity (0.25 → 31). Found \(soft).

            `MIDIFileExporter.melodyEvents` writes `Int(n.velocity * 127 * velScale)`. If a \
            flat velocity is now written instead, `docs/architecture.html` must go back to \
            listing per-note velocity as ROADMAP in the same commit (#456) — that sentence is \
            true only because this byte is.
            """)
        XCTAssertTrue(loud.contains(120), """
            The exported .mid does not carry note 67's own velocity (0.95 → 120). Found \(loud).
            """)
        XCTAssertNotEqual(soft, loud, """
            Both notes exported at the SAME velocity byte. Per-note velocity that is constant \
            per file is not per-note velocity; the page's LIVE tag would be wrong.
            """)
    }

    // MARK: - claim 3 — the page does not sell the shipped third as roadmap

    /// The prose half. It bans ONLY the velocity third from a roadmap sentence; "automation"
    /// and "voice-leading" stay freely sayable as roadmap, because they are (#364).
    func testTheArchitecturePageDoesNotCallPerNoteVelocityRoadmap() throws {
        let html = try rawFile(Self.architecture)
        for sentence in sentences(in: html) where sentence.lowercased().contains("per-note velocity") {
            let lower = sentence.lowercased()
            XCTAssertFalse(lower.contains("roadmap") || lower.contains("planned"), """
                `docs/architecture.html` calls per-note velocity roadmap: "\(sentence)"

                IT SHIPS. `BioComposer` writes a varying velocity per note (claim 1 pins one of \
                the five sources) and `MIDIFileExporter` writes it into the file (claim 2 reads \
                the actual bytes). What IS roadmap in that row is automation and richer \
                voice-leading — name those two, in their own sentence, without the third.

                If per-note velocity was genuinely removed, claims 1 and 2 are red too — read \
                those failures first.
                """)
        }
    }

    // MARK: - Helpers

    private struct AnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    /// Same shape as the rest of the bundle — a SKIP without a checkout (the guard cannot
    /// look), a FAILURE when a named file moved (#454: a skip passes CI).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    /// Raw text, no Swift comment stripping — this reads HTML.
    /// ⚠️ A MISSING FILE THROWS (#454). A scan that silently finds nothing when the page moved
    /// reports "nothing wrong" instead of "I could not look".
    private func rawFile(_ relativePath: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw AnchorMissing(reason: """
                `\(relativePath)` is unreadable. If the page moved, re-anchor this guard in the \
                same commit rather than letting it pass on an empty read.
                """)
        }
        return text
    }

    /// Tag-stripped sentences. The boundary skips a run of closing marks after the terminator,
    /// because `.)` glues two sentences together otherwise and a checker with false alarms is a
    /// checker nobody reads (#665). Same shape as the sweep in
    /// `TheMPEDimensionsReachNoVoiceTests`; it is duplicated rather than shared because these
    /// two guards must be independently deletable, and the helper is nine lines.
    private func sentences(in html: String) -> [String] {
        var text = ""
        var inTag = false
        for ch in html {
            if ch == "<" { inTag = true; text.append(" "); continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { text.append(ch) }
        }
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&mdash;", with: "—")
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            current.append(ch)
            i += 1
            guard ch == "." || ch == "!" || ch == "?" else { continue }
            var j = i
            while j < chars.count, ")\"']»".contains(chars[j]) { j += 1 }
            guard j < chars.count, chars[j].isWhitespace else { continue }
            out.append(current)
            current = ""
            i = j
        }
        out.append(current)
        return out
            .map { $0.split(separator: " ").joined(separator: " ") }
            .filter { !$0.isEmpty }
    }
}
