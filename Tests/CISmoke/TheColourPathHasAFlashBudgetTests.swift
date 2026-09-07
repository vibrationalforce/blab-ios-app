import XCTest
@testable import Echoelmusic

/// #1091 — the COLOUR path gets its constants named and its flash status pinned honestly.
///
/// WHY IT EXISTS. `FlashGuardTests.testEveryReachableLookObeysTheThreeHzLaw` bounds the scalar
/// FIELD of every look. Colour travels a separate path — five note clouds whose weight, colour
/// and place are eased on the CPU with SEVEN bare literals in `MetalBioView`, plus the Prism
/// look's A→B crossfade and its retrigger gate — and no test read any of them. A look whose
/// colour oscillated would have passed the four-row table while flashing. Hoisting the
/// constants into `FlashGuard` (the `maxPulseRateHz` repair applied to colour) is the
/// mechanical half; the honest half is what this file refuses to claim.
///
/// ⚠️ THE HOIST IS NOT A PROOF, and claim 3 exists so nobody reads it as one. A first-order
/// lowpass driven on/off at the WCAG rate still passes `tanh(1/(4·hz·tau))` of the swing:
/// ≈ 73 % for a finger cloud (tau 0.09), ≈ 27 % for a generative cloud (tau 0.30). So the time
/// constants do NOT rate-limit the colour path below the 10 % luminance gate; whether a
/// cloud's swing is a WCAG 2.3.1 flash is a PHOTOMETRIC question (relative luminance moved,
/// over what fraction of the field — the shader's cloud radius is `0.42 · spread`, spread up
/// to 1.92 in a square field) that no static read settles.
///
/// NEEDS-FOUNDER-VERIFY: a 5-second screen recording, default Water look, ONE finger
/// drumming the visual at roughly 4 taps per second, then the same with the generative bed
/// playing 16ths. `watch-clip` measures per-frame relative luminance from the frames; that
/// measurement, not this file, decides whether the touch path needs a spatial gate.
///
/// ⚠️ GRADED HONESTLY (#464): claim 1 is STRUCTURAL (the names replace literals; red on the
/// parent by construction, green here). Claims 2 and 3 are PREVENTIVE pins. Claim 4 anchors
/// the two shader numbers the photometric argument will need, so they cannot drift silently.
final class TheColourPathHasAFlashBudgetTests: XCTestCase {

    private func source(_ relative: String) -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    /// Code only: the part of each line before a `//`, so a comment that QUOTES a literal
    /// (this slice leaves several on purpose) is not booked as a call site.
    private func codeLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            String(line).components(separatedBy: "//").first ?? ""
        }
    }

    private func count(_ needle: String, in lines: [String]) -> Int {
        lines.reduce(0) { $0 + $1.components(separatedBy: needle).count - 1 }
    }

    // 1 — the renderer reads the named constants, and the bare literals are gone from CODE.
    func testTheRendererReadsTheNamedConstants() {
        let lines = codeLines(source("Sources/Echoelmusic/Views/MetalBioView.swift"))
        let expected: [(name: String, atLeast: Int)] = [
            ("FlashGuard.cloudRiseTauTouch", 1), ("FlashGuard.cloudRiseTauGenerative", 1),
            ("FlashGuard.cloudFallTau", 1), ("FlashGuard.cloudColourChaseTau", 1),
            ("FlashGuard.cloudPositionChaseTau", 1), ("FlashGuard.prismFadeTau", 1),
            ("FlashGuard.prismRetriggerGate", 1)
        ]
        for item in expected {
            XCTAssertGreaterThanOrEqual(count(item.name, in: lines), item.atLeast, """
                `MetalBioView` no longer reads `\(item.name)`. The colour-path constants live in \
                `FlashGuard` so the 3 Hz argument can read them; a literal typed back at the \
                call site is a drift surface no naming census finds (#864).
                """)
        }
        for literal in ["tau: 0.18,", "tau: 0.25,", "? 0.09 : 0.30", "colorNoteFade >= 0.6"] {
            XCTAssertEqual(count(literal, in: lines), 0, """
                `MetalBioView` carries the bare colour-path literal `\(literal)` in code again. \
                Read `FlashGuard.cloudRiseTauTouch`'s doc, then use the named constant.
                """)
        }
    }

    // 2 — the survival formula is what its doc says, and it fails CLOSED.
    func testSquareWaveSurvivalIsTheLowpassFormula() {
        XCTAssertEqual(FlashGuard.squareWaveSurvival(hz: 3, tau: 0.09), 0.7286, accuracy: 0.001)
        XCTAssertEqual(FlashGuard.squareWaveSurvival(hz: 3, tau: 0.30), 0.2708, accuracy: 0.001)
        XCTAssertEqual(FlashGuard.squareWaveSurvival(hz: 8, tau: 0.30), 0.1037, accuracy: 0.001)
        XCTAssertGreaterThan(FlashGuard.squareWaveSurvival(hz: 2, tau: 0.3),
                             FlashGuard.squareWaveSurvival(hz: 4, tau: 0.3), "faster wave → less survives")
        XCTAssertGreaterThan(FlashGuard.squareWaveSurvival(hz: 3, tau: 0.1),
                             FlashGuard.squareWaveSurvival(hz: 3, tau: 0.5), "longer tau → less survives")
        for bad in [(Double.nan, 0.3), (3.0, Double.nan), (0.0, 0.3), (3.0, 0.0), (-1.0, 0.3)] {
            XCTAssertEqual(FlashGuard.squareWaveSurvival(hz: bad.0, tau: bad.1), 1, """
                A non-finite or non-positive input must return 1 (the whole swing survives) so a \
                caller asserting "attenuated enough" fails CLOSED — the `.infinity` direction \
                `effectiveFieldHz` chose.
                """)
        }
    }

    // 3 — THE HONEST STATUS. The time constants do not rate-limit the colour path below the
    //     general-flash gate. If this ever flips (a much longer tau), the colour path HAS a
    //     rate proof: delete this claim, and say so in the plan and in `FlashGuard`'s doc in
    //     the same commit — do not leave a pin asserting a weakness that is gone (#364).
    func testTheTimeConstantsAreNotTheColourPathsSafetyArgument() {
        let touch = FlashGuard.squareWaveSurvival(hz: FlashGuard.maxFlashHz,
                                                  tau: FlashGuard.cloudRiseTauTouch)
        let generative = FlashGuard.squareWaveSurvival(hz: FlashGuard.maxFlashHz,
                                                       tau: FlashGuard.cloudRiseTauGenerative)
        XCTAssertGreaterThan(touch, FlashGuard.luminanceDeltaThreshold, """
            A finger cloud's rise (tau \(FlashGuard.cloudRiseTauTouch)) now attenuates a 3 Hz \
            on/off drive below the 10 % gate. That would be a genuine rate proof for the touch \
            path — record it, and retire this claim with it.
            """)
        XCTAssertGreaterThan(generative, FlashGuard.luminanceDeltaThreshold, """
            A generative cloud's rise (tau \(FlashGuard.cloudRiseTauGenerative)) now attenuates \
            a 3 Hz on/off drive below the 10 % gate. Same instruction as above.
            """)
        // The Prism gate's switch bound: 1 / (tau · ln(1/(1 − gate))) switches per second,
        // halved for opposing PAIRS. It sits on the ceiling; it must not sit above it.
        let switchesPerSecond = 1.0 / (FlashGuard.prismFadeTau
                                       * Foundation.log(1.0 / (1.0 - FlashGuard.prismRetriggerGate)))
        XCTAssertLessThanOrEqual(switchesPerSecond / 2.0, FlashGuard.maxFlashHz + 0.05, """
            The Prism crossfade can now switch \(switchesPerSecond) times per second — more than \
            two opposing pairs above the WCAG ceiling. Lengthen `prismFadeTau` or raise \
            `prismRetriggerGate`.
            """)
    }

    // 4 — the two shader numbers the photometric half will be argued from are still there.
    func testTheShaderCloudRadiusAnchorsStillExist() {
        let view = source("Sources/Echoelmusic/Views/MetalBioView.swift")
        XCTAssertTrue(view.contains("float radius = 0.42 * spread;"),
                      "The cloud radius line moved or changed — re-derive the spatial-extent argument in `FlashGuard.cloudRiseTauTouch`'s doc and here.")
        XCTAssertTrue(view.contains("clamp(u.spread, 0.4, 1.6)"),
                      "The spread clamp moved or changed — the 'spread up to 1.92' figure in `FlashGuard`'s doc is derived from it.")
    }
}
