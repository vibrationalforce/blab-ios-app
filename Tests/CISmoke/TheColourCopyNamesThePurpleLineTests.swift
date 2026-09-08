// TheColourCopyNamesThePurpleLineTests.swift
// Echoel — the user-facing colour copy must not claim a pure CIE rendering. BLOCKING bundle.
//
// #1143, closing a CONFIRMED finding of the visual deep audit (AUDIT_VISUAL_2026-09-06,
// "The Field caption overstates"). Three sentences a PLAYER reads said the shown colour is
// the CIE 1931 rendering of the tone's transposed frequency. Measured, that is true for
// 60.8 % of the octave circle and false for the rest.
//
// ⭐ THE MEASUREMENT, re-derived here in claim 3 from the three nm constants rather than
// quoted: `toneLinearRGB` renders the pure spectral colour only while `t` is inside
// [tRed, tViolet] = [0.285402219, 0.893084796]. Outside it — the seam where the deep-red
// edge wraps to the deep-violet edge — the colour is a linear blend of the 640 nm and
// 420 nm endpoint colours along the CIE purple line. The seam is `tRed + 1 - tViolet`
// = 0.392317, i.e. 39.2 % of every octave. At A4 = 440 Hz five of the twelve pitch classes
// (E · F · F♯ · G · G♯) land in it.
//
// ⚠️ THE PURPLE LINE IS NOT A CHEAT, and the copy must not read as an apology for one. The
// CIE 1931 chromaticity diagram is closed by the purple line; the colours on it are real
// (mixtures of red and violet light), just not monochromatic. Closing the tone circle over
// it is what gives EVERY pitch class a colour instead of leaving a gap. What was wrong was
// only the claim that each shown colour is a single rendered wavelength.
//
// ⛔ ONE SENTENCE WAS WORSE THAN AN OVERSTATEMENT AND IS RETRACTED, claim 2. The
// `.redNearInfrared` entry said "where a tone transposes past ~700 nm it simply leaves
// visible colour behind". That is true of `visibleWavelength(forToneHz:)`, the RAW readout,
// and false of the rendered colour, which closes over the seam and never goes dark. It told
// a player a tone can become invisible when no tone ever does.
//
// ⚠️ THIS GUARD FORBIDS NO IMPROVEMENT (#364). It does not require the purple-line closure
// to stay — it requires the COPY to match whatever the mapping does. If a future cycle
// replaces the seam with something better, this file goes red and its messages name the
// three copy homes that must move in the same commit (#456).
//
// ⚠️ AND THE TWO ANSWERS STAY TWO, claim 4: `visibleWavelength(forToneHz:)` must survive as
// the honest physical READOUT. A session that "unifies" the readout onto the closed circle
// would delete the number that makes the seam explainable in the first place.

import XCTest

final class TheColourCopyNamesThePurpleLineTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let science = "Sources/Echoelmusic/Studio/LightScienceInfo.swift"
    private static let colour = "Sources/Echoelmusic/Core/SpectralColor.swift"

    private func code(_ rel: String) throws -> String {
        let r = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: r.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(r.path)") }
        let path = r.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: path.path) else {
            struct AnchorMissing: Error { let path: String }
            throw AnchorMissing(path: rel)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - 1 · All three player-facing homes name the seam

    func testEveryUserFacingColourClaimNamesThePurpleLine() throws {
        let studio = try code(Self.studio)
        let science = try code(Self.science)

        XCTAssertEqual(count("closed over the CIE purple line where deep red meets deep violet, so every tone has a colour.",
                             in: studio), 1, """
            The Field colour caption no longer names the purple line. It is the one sentence a \
            player reads about where the colour comes from, and a plain "rendered via CIE 1931" \
            is false for 39.2 % of the octave (claim 3 re-derives that). Say what the mapping \
            does, or change the mapping — do not shorten the caption back to the overstatement.
            """)

        XCTAssertEqual(count("closed over the CIE purple line where deep red meets deep violet. About 39 % of each octave lands on that seam",
                             in: science), 1, """
            LightScienceInfo `.scope` lost its purple-line sentence. This is the Learn entry \
            that explains the whole tone->light mapping; it is the home where the 39 % belongs, \
            because a science explainer is the right place for the number. Claim 3 pins that \
            the number still follows from the nm constants.
            """)

        XCTAssertEqual(count("the colour mapping closes over the CIE purple line and continues into violet, so every tone keeps a colour.",
                             in: science), 1, """
            LightScienceInfo `.redNearInfrared` lost the correction of its retracted sentence. \
            See claim 2 — the old wording told a player a tone can go dark, which no tone does.
            """)
    }

    // MARK: - 2 · The retracted sentence stays retracted

    func testTheToneNeverLeavesVisibleColourBehind() throws {
        let science = try code(Self.science)
        XCTAssertEqual(count("it simply leaves visible colour behind", in: science), 0, """
            The retracted sentence is back in LightScienceInfo. It confuses the RAW wavelength \
            readout (`visibleWavelength(forToneHz:)`, which really does run past the visible \
            edge) with the RENDERED colour (`toneLinearRGB`, which closes over the purple line \
            and never goes dark). Both exist on purpose — claim 4 pins that they stay two \
            answers — but only the readout may be described as leaving the visible band.
            """)
    }

    // MARK: - 3 · The 39 % in the copy is derived, not remembered

    func testTheSeamShareIsWhatTheConstantsSay() throws {
        let colour = try code(Self.colour)

        // The two edges of the pure-spectral span, as the file itself pins them for the shader.
        XCTAssertEqual(count("\"0.285402219\"", in: colour), 1, """
            `tRedMetalLiteral` changed. It is the Swift/MSL twin of `tRed`, and the 39 % in the \
            Learn copy is `tRed + 1 - tViolet`. Re-derive the share and move the copy with it.
            """)
        XCTAssertEqual(count("\"0.893084796\"", in: colour), 1, """
            `tVioletMetalLiteral` changed — same consequence as the red edge above.
            """)

        // Re-derive the share from the three nm constants, so this is a measurement and not
        // a transcription of the two literals above.
        let anchor = 780.0, redEdge = 640.0, violetEdge = 420.0
        for (name, nm) in [("anchorNm", anchor), ("redEdgeNm", redEdge), ("violetEdgeNm", violetEdge)] {
            XCTAssertEqual(count("\(name): Double = \(nm)", in: colour), 1, """
                `\(name)` is no longer \(nm) in SpectralColor. The seam share, and therefore the \
                "About 39 %" sentence in LightScienceInfo `.scope`, is computed from these three \
                numbers. Recompute `log2(anchor/red) + 1 - log2(anchor/violet)` and move the copy.
                """)
        }
        let tRed = log2(anchor / redEdge)
        let tViolet = log2(anchor / violetEdge)
        let seam = tRed + 1 - tViolet
        // Measured margin today is 4.23e-7; the tolerance is deliberately looser than that so a
        // libm that rounds `log2` differently cannot turn a correct constant into a red gate.
        XCTAssertEqual(seam, 0.392317, accuracy: 0.00001, """
            The seam share moved off 0.392317. The Learn copy says "About 39 % of each octave"; \
            once the share leaves 0.385...0.394 that word is wrong.
            """)
        XCTAssertGreaterThan(seam, 0.385, "copy says about 39 %")
        XCTAssertLessThan(seam, 0.395, "copy says about 39 %")
    }

    // MARK: - 4 · Counterweight — the raw readout stays a second, different answer

    func testTheRawWavelengthReadoutSurvives() throws {
        let colour = try code(Self.colour)
        XCTAssertGreaterThanOrEqual(count("func visibleWavelength(forToneHz", in: colour), 1, """
            `visibleWavelength(forToneHz:)` is gone. It is the HONEST physical number ("F ~ 780 nm \
            edge") and it is deliberately NOT the same answer as `toneLinearRGB`, which closes the \
            circle so every tone has a colour. Deleting it in the name of one truth removes the \
            number that makes the seam explainable — and makes the `.redNearInfrared` correction \
            in claim 2 unreadable.
            """)
        XCTAssertGreaterThanOrEqual(count("func toneLinearRGB(forToneHz", in: colour), 1, """
            `toneLinearRGB(forToneHz:)` is gone — the rendering half of the pair. Every claim in \
            this file describes what it does; if it is replaced, all three copy homes in claim 1 \
            must be rewritten in the same commit.
            """)
    }
}
