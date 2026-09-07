import XCTest
@testable import Echoelmusic

/// #1072 — ONE definition of "the visual with the sky mixed in".
///
/// ⭐ END-TO-END BEHAVIOUR (§1's strong kind), not a source-text scan. `WeatherMood.visualValues`
/// is a pure, `public`, Foundation-only function over value types, so this file drives the real
/// arithmetic rather than asserting where it is written. That is the whole point of lifting it:
/// the mix used to live inside a `private func` on a `View` no test bundle can instantiate, and
/// the only thing a guard could say about it was where the letters sat.
///
/// WHY IT WAS LIFTED: two surfaces render the visual and only one mixed. The phone blended four
/// values; `ExternalStageScene` handed the same four keys to `MetalBioView` raw, so a projector
/// silently dropped the weather tint (measured, #1071). Two spellings of one decision is the
/// #416 defect — and this is what it looks like a year later: not an argument anyone can see,
/// but a picture that changes when a cable goes in.
///
/// ⚠️ THIS FILE DOES NOT CLOSE #1071. The beamer still renders raw; the helper exists and the
/// phone calls it. `TheBeamerDrawsTheSamePictureTests` still holds that gap and still goes red
/// the day it closes.
final class TheWeatherVisualMixHasOneDefinitionTests: XCTestCase {

    private let base = WeatherMood.VisualValues(hue: 0.20, saturation: 0.40,
                                                intensity: 0.60, motion: 0.80)

    private func sky(hue: Float, saturation: Float, glow: Float, motion: Float)
        -> WeatherMood.Contribution {
        // Build from a real snapshot so the struct's OTHER fields are whatever the shipped
        // mapping produces, then override the four this function reads. Constructing a
        // Contribution by hand would pin a memberwise init this test has no business owning.
        var c = WeatherMood.contribution(for: WeatherSnapshot(temperatureC: 12,
                                                              condition: .clear,
                                                              isDaylight: true,
                                                              windKph: 5))
        c.hue = hue
        c.saturation = saturation
        c.glowTarget = glow
        c.motionTarget = motion
        return c
    }

    private static let allOff = WeatherMood.VisualMixers(hue: 0, saturation: 0,
                                                         glow: 0, movement: 0)
    private static let allFull = WeatherMood.VisualMixers(hue: 1, saturation: 1,
                                                          glow: 1, movement: 1)

    // 1 — NEUTRALITY, both ways in, and the two ways are NOT equally exact. That asymmetry is
    // the finding this claim recorded rather than papered over.
    //
    // ⛔ THE FIRST DRAFT ASSERTED BOTH WITH `XCTAssertEqual` AND WOULD HAVE BEEN RED ON A
    // CORRECT TREE — the third time this bundle has caught that shape (#650, #960, #1069). Its
    // message even said "bit-identically", which is false and was false before #1072 too: the
    // shared mix is `Float`, the visual values are `Double`, so a base that goes through
    // `blend` comes back narrowed (0.20 → 0.20000000298…) no matter what the mixer says. The
    // old `private func` narrowed exactly the same way; nothing regressed, my assertion was
    // simply stricter than the arithmetic it was pointed at.
    //
    // So the two halves are pinned at the strength each one actually has:
    //   · `contribution: nil` short-circuits BEFORE any arithmetic → exactly `base`.
    //   · every mixer at 0 still runs the crossfade → `base` to within Float precision.
    // Deliberately NOT "fixed" by short-circuiting on all-zero mixers: that would change
    // shipped behaviour to make a test prettier, and ~3e-9 on a hue is not a picture anyone
    // can see.
    func testNoSkyReturnsTheUsersOwnValuesExactly() {
        XCTAssertEqual(WeatherMood.visualValues(base: base, mixers: Self.allFull,
                                                contribution: nil),
                       base,
                       """
                       `contribution: nil` no longer returns the user's values untouched. That \
                       case IS "weather off, or no snapshot yet" — the old guard clause in \
                       `FloatingVisualWindow.weatheredVisuals()`. It short-circuits before any \
                       arithmetic, so it is the one path that must be EXACT; anything else \
                       means turning weather off changes the picture.
                       """)
    }

    func testEveryMixerAtZeroReturnsTheBaseWithinFloatPrecision() {
        let out = WeatherMood.visualValues(base: base, mixers: Self.allOff,
                                           contribution: sky(hue: 0.9, saturation: 0.9,
                                                             glow: 0.9, motion: 0.9))
        for (name, got, want) in [("hue", out.hue, base.hue),
                                  ("saturation", out.saturation, base.saturation),
                                  ("intensity", out.intensity, base.intensity),
                                  ("motion", out.motion, base.motion)] {
            XCTAssertEqual(got, want, accuracy: 1e-6, """
                The `\(name)` mixer at 0 no longer returns the base, even though the sky is \
                saying something loud. `WeatherMood.blend`'s doc promises intensity 0 = base \
                unchanged; a mix that drifts at zero is a control that cannot be switched off. \
                (The tolerance is Float32 narrowing, not slack — see the note above.)
                """)
        }
    }

    // 2 — FULL mix lands exactly on the sky. Together with claim 1 this pins both ends of the
    // crossfade, so a sign flip or a swapped operand cannot hide in the middle.
    func testFullMixLandsOnTheSky() {
        let out = WeatherMood.visualValues(base: base, mixers: Self.allFull,
                                           contribution: sky(hue: 0.10, saturation: 0.20,
                                                             glow: 0.30, motion: 0.40))
        XCTAssertEqual(out.hue, 0.10, accuracy: 1e-6)
        XCTAssertEqual(out.saturation, 0.20, accuracy: 1e-6)
        XCTAssertEqual(out.intensity, 0.30, accuracy: 1e-6)
        XCTAssertEqual(out.motion, 0.40, accuracy: 1e-6)
    }

    // 3 — ⭐ THE PAIRING, and it is the reason this file exists rather than a scan. The mixer
    // names do NOT match the visual parameter names: `glow` drives INTENSITY, `movement` drives
    // MOTION. A hand-written second copy gets exactly this wrong, and nothing would look broken
    // until someone moved one slider and the wrong thing changed.
    func testEachMixerMovesOnlyItsOwnParameter() {
        let loud = sky(hue: 1, saturation: 1, glow: 1, motion: 1)
        let cases: [(String, WeatherMood.VisualMixers, KeyPath<WeatherMood.VisualValues, Double>)] = [
            ("hue",        WeatherMood.VisualMixers(hue: 1, saturation: 0, glow: 0, movement: 0), \.hue),
            ("saturation", WeatherMood.VisualMixers(hue: 0, saturation: 1, glow: 0, movement: 0), \.saturation),
            ("glow",       WeatherMood.VisualMixers(hue: 0, saturation: 0, glow: 1, movement: 0), \.intensity),
            ("movement",   WeatherMood.VisualMixers(hue: 0, saturation: 0, glow: 0, movement: 1), \.motion),
        ]
        for (name, mixers, moved) in cases {
            let out = WeatherMood.visualValues(base: base, mixers: mixers, contribution: loud)
            XCTAssertEqual(out[keyPath: moved], 1.0, accuracy: 1e-6, """
                The `\(name)` mixer no longer moves the parameter it is paired with. The names \
                are deliberately unlike (`glow` → intensity, `movement` → motion), which is the \
                pairing a second hand-written copy gets wrong.
                """)
            for other in [\WeatherMood.VisualValues.hue, \.saturation, \.intensity, \.motion]
            where other != moved {
                XCTAssertEqual(out[keyPath: other], base[keyPath: other], accuracy: 1e-6, """
                    The `\(name)` mixer moved a parameter that is not its own. Each mixer is an \
                    independent user control; cross-talk means one slider silently edits another.
                    """)
            }
        }
    }

    // 4 — COUNTERWEIGHT (#343): the phone actually CALLS this. Without it the file would stay
    // green over a helper nobody uses — a pure core with no caller, which this repo's register
    // treats as its own category of finding.
    func testTheWindowCallsTheSharedHelperRatherThanItsOwnCopy() throws {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        let code = SourceText.codeOnly(try XCTUnwrap(String(contentsOf: url, encoding: .utf8)))
        XCTAssertTrue(code.contains("WeatherMood.visualValues("), """
            `FloatingVisualWindow` no longer calls the shared mix. If it grew its own copy back, \
            that is the #416 divergence #1071 measured, arriving from the other direction.
            """)
        XCTAssertFalse(code.contains("WeatherMood.blend(base:"), """
            `FloatingVisualWindow` calls `WeatherMood.blend` directly again. The whole point of \
            #1072 is that the four-value mix has ONE spelling; a direct `blend` here is that \
            spelling being written a second time.
            """)
    }
}
