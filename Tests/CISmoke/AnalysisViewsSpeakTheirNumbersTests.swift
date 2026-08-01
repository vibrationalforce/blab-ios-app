// AnalysisViewsSpeakTheirNumbersTests.swift
// Echoel — a meter whose number a screen reader cannot hear is not a meter.
//
// WHAT THIS GUARDS (#352). The #347 analysis views each pair a PICTURE (a `Canvas` — an
// oscilloscope trace, spectrum bars, a Poincaré cloud) with a NUMBER underneath (peak
// dBTP, the loudest partial and its note, SD1/SD2). Uncodixfy puts the number first on
// purpose: "legible numbers first, visualization second". For a VoiceOver user the number
// is not merely first, it is the ONLY thing there is — a Canvas has nothing readable in it.
//
// The failure mode is one modifier: `.accessibilityElement(children: .combine)` on the
// enclosing `VStack`. It folds the children into a single element and DISCARDS their
// labels; an explicit `.accessibilityLabel` on that same element then replaces whatever
// survived. The result reads "Spectrum analyser" and stops. The picture — the part that
// legitimately wants a summary label, because it has no text — ends up being the only
// thing described, and the measurement is silent.
//
// ⛔ THIS IS A REGRESSION I SHIPPED, ONE SLICE AFTER FIXING IT. `AnalysisScopeView` (Slice 1)
// carries a comment naming this exact mistake and why it was undone. `AnalysisSpectrumView`
// (Slice 2) reproduced it anyway, because I wrote the second view from the SHAPE of the
// first rather than from its reasons. A comment in a sibling file is not a guard: it only
// reaches a reader who happens to open that file. This is the guard.
//
// ⭐ WHY THE WHOLE CLASS AND NOT THE ONE STRING. Slice 4 (stereo/spatial image) is still to
// come and will be a fourth picture-plus-number pair written from the same template. Pinning
// the spectrum's exact sentence would guard the one view that has already been fixed and
// none of the ones that can still repeat it. So the file scans every `Analysis*View`.
//
// ⚠️ A green here does not mean VoiceOver reads well. It means the picture and the number
// are SEPARATE elements and the number's label is a computed value rather than a fixed
// string. Whether the resulting sentence is understandable is a device check with VoiceOver
// on. Source scan, no simulator; SKIPS rather than passes if the tree is not at this file's
// compile-time path.

import Foundation
import XCTest

final class AnalysisViewsSpeakTheirNumbersTests: XCTestCase {

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    /// Every `Analysis*View.swift` under `Studio/`, discovered rather than listed — a new
    /// analysis view is covered the moment it lands, which is the whole point (Slice 4 is
    /// still to come).
    private func analysisViews() throws -> [(name: String, lines: [String])] {
        let dir = try repoRoot().appendingPathComponent("Sources/Echoelmusic/Studio")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("Analysis") && $0.hasSuffix("View.swift") }
            .sorted()
        return try names.map { name in
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            return (name, lines)
        }
    }

    /// The discovery must actually find something. A filter that silently matches nothing is
    /// the `continue-on-error` lie in another costume: every assertion below would vacuously
    /// pass over an empty list.
    func testTheScanFindsTheAnalysisViews() throws {
        let views = try analysisViews()
        // ⛔ `views.map(\.name)` does NOT compile: Swift key paths cannot address a TUPLE
        // component, and the element type here is `(name:lines:)`. It reads perfectly and is
        // rejected by the parser — the exact class of mistake that takes the blocking gate
        // red for a whole cycle, since nothing here can be compiled locally.
        let names = views.map { $0.name }
        XCTAssertGreaterThanOrEqual(views.count, 3, """
            Found \(views.count) Analysis*View files (\(names)). Three shipped \
            with #347 — scope, spectrum, Poincaré. If they were renamed, re-anchor the \
            discovery in the same commit; a scan that finds nothing passes everything.
            """)
    }

    func testNoAnalysisViewCombinesItsPictureWithItsNumber() throws {
        for view in try analysisViews() {
            let offenders = view.lines.filter { $0.contains("accessibilityElement(children: .combine)") }
            XCTAssertTrue(offenders.isEmpty, """
                \(view.name) folds its children into one accessibility element. `.combine` \
                DISCARDS the children's labels, and an explicit `.accessibilityLabel` on the \
                same element replaces what is left — so VoiceOver reads the picture's summary \
                and never the measurement, which for a non-sighted user is the entire content \
                of the view. Put `.accessibilityElement()` on the Canvas alone and let the \
                readout below it stay its own element (see `AnalysisScopeView`).
                """)
        }
    }

    func testEveryAnalysisViewHasAComputedLabelForItsReadout() throws {
        for view in try analysisViews() {
            // A label whose argument is NOT a string literal — i.e. one carrying a live
            // value. Every one of these views has a number to say; a file where all labels
            // are fixed strings is one where the number is not spoken.
            let computed = view.lines.filter { line in
                guard let r = line.range(of: ".accessibilityLabel(") else { return false }
                let rest = line[r.upperBound...].drop { $0 == " " }
                guard let first = rest.first else { return false }
                return first != "\""
            }
            XCTAssertFalse(computed.isEmpty, """
                \(view.name) has no accessibility label built from a value — every label in \
                it is a fixed string. The number under the picture is the science-first \
                content of these views (Uncodixfy: "legible numbers first"); a screen reader \
                that only hears the title of the graph gets none of it.
                """)
        }
    }

    // MARK: - The spoken form is a sentence, not the printed glyphs

    func testTheSpectrumSpeaksWordsAndNotPunctuation() throws {
        guard let spectrum = try analysisViews().first(where: { $0.name == "AnalysisSpectrumView.swift" }) else {
            throw XCTSkip("AnalysisSpectrumView.swift is gone — remove this case with it")
        }
        let spoken = spectrum.lines.filter { $0.contains("spoken = \"") }
        XCTAssertFalse(spoken.isEmpty, """
            The spectrum readout no longer builds a separate spoken string. The printed form \
            is "220.1 Hz · A2 +5 ct"; VoiceOver renders "·" as "middle dot" and U+2212 as \
            "minus sign" mid-number, so read literally it arrives as a list of glyph names \
            rather than a reading a performer can follow.
            """)
        for line in spoken {
            XCTAssertFalse(line.contains(" · "), """
                A spoken label still carries the "·" separator: \
                \(line.trimmingCharacters(in: .whitespaces))
                """)
            XCTAssertFalse(line.contains(" ct\""), """
                A spoken label still abbreviates cents as "ct": \
                \(line.trimmingCharacters(in: .whitespaces))
                """)
        }
        // Zero is its own case on purpose. A naive sign test says "plus zero cents sharp";
        // a musician says "in tune", and the readout is for musicians.
        XCTAssertTrue(spectrum.lines.contains { $0.contains("if cents == 0") }, """
            The zero-cent case is gone from the spoken form, so an exactly-in-tune note will \
            be announced as sharp or flat by zero cents.
            """)
    }
}
