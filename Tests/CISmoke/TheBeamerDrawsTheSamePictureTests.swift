import XCTest
@testable import Echoelmusic

/// #1071 — THE BEAMER DOES NOT DRAW THE PHONE'S PICTURE, AND THIS FILE IS THE RECORD OF THAT.
///
/// ⚠️ READ THIS BEFORE THE ASSERTIONS. This guard PINS A KNOWN GAP. It is written to go RED on
/// the day the gap is closed, and the message on every claim says so. That is deliberate and it
/// is the #364 line: a guard must never forbid the fix, so instead of asserting the divergence
/// is correct, each claim asserts the two halves that MAKE it a divergence and names the repair.
/// Closing it is a green outcome that reddens this file; delete the file in that commit.
///
/// MEASURED: `FloatingVisualWindow.weatheredVisuals()` blends FOUR values — hue, saturation,
/// intensity, motion — through `WeatherMood.blend` against the live sky, each behind its own
/// user mixer. `ExternalStageScene`'s view reads the same four `@AppStorage` keys and hands them
/// to `MetalBioView` RAW. So attaching a projector silently drops the weather tint mid-show.
///
/// WHY IT IS A GAP AND NOT A CHOICE: `ExternalDisplayScene` already states the rule for its own
/// `autoMode` reader (#609) — "without this reader, plugging in a projector would silently strip
/// the Auto mode's visual half mid-show and the swap would read as a broken look." Weather is
/// the same class of half. The founder's open question ("Beamer wettergemischt oder roh?") was
/// asked before anyone measured which one it currently does.
///
/// ⚠️ SOURCE-TEXT SCAN (§1). It proves where the blend is written and where it is not. Whether a
/// projector looks right is a DEVICE PROBE and stays open.
final class TheBeamerDrawsTheSamePictureTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(path) could not be read — a missing anchor is a finding.")
            return ""
        }
        return SourceText.codeOnly(text)
    }

    private static let window = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"
    private static let scene  = "Sources/Echoelmusic/Studio/ExternalDisplayScene.swift"

    // 1 — the phone really does blend. Without this the whole finding is imaginary, and a slice
    // that removed the blend entirely would "close" the gap by making both sides equally raw.
    func testThePhoneBlendsTheSkyIntoTheLook() throws {
        let code = try source(Self.window)
        XCTAssertTrue(code.contains("WeatherMood.blend(base:"), """
            `FloatingVisualWindow` no longer blends the sky into the look. If the weather visual \
            mix was RETIRED, that closes the #1071 divergence from the wrong end — the two \
            surfaces would agree because neither does anything. Say so explicitly and delete \
            this whole file in that commit; do not let it pass silently.
            """)
        XCTAssertTrue(code.contains("private func weatheredVisuals()"), """
            `weatheredVisuals()` is gone or renamed. It is the one place the four blended values \
            are produced, and the recorded repair for #1071 is to LIFT it into a shared pure \
            helper both surfaces call (#416). Re-anchor here if it moved, and update the ⛔ note \
            in `ExternalDisplayScene` in the same commit (#456).
            """)
    }

    // 2 — THE GAP ITSELF. This is the assertion that must go red when the repair lands.
    func testTheBeamerStillRendersTheRawKeys() throws {
        let scene = try source(Self.scene)
        XCTAssertFalse(scene.contains("WeatherMood"), """
            ⭐ THIS IS THE GOOD FAILURE. `ExternalDisplayScene` now names `WeatherMood`, which \
            means the beamer has been taught the phone's blend and the #1071 divergence is \
            closed. Nothing is broken.

            DELETE THIS FILE in that same commit, and sweep the two ⛔ notes it points at — the \
            one above `ExternalStageView`'s key block and the one above \
            `FloatingVisualWindow.weatheredVisuals()`. A guard that records a gap outlives its \
            purpose the moment the gap is gone (#364), and leaving it would forbid the fix.

            Check while you are there that the blend went through ONE shared helper rather than \
            being copied — two spellings of one decision is the defect #416 names, and this \
            divergence is what a copy looks like a year later.
            """)
        // COUNTERWEIGHT (#367): the scene must still RENDER, or claim 2 passes vacuously on a
        // tree where the external path was deleted altogether.
        XCTAssertTrue(scene.contains("MetalBioView(capturesVideo: false"), """
            `ExternalStageScene` no longer mounts the renderer, so the claim above proves \
            nothing — a file with no picture in it trivially contains no `WeatherMood`. If the \
            external-screen path was removed, delete this file with it.
            """)
    }

    // 3 — the RULE the gap is measured against is still written down. Without it, a later reader
    // has a divergence and no reason to think it is wrong, and the cheapest "fix" is to delete
    // the notes rather than the gap.
    func testTheSceneStillStatesTheRuleItBreaks() throws {
        let scene = try source(Self.scene)
        XCTAssertTrue(scene.contains("autoMode"), """
            `ExternalStageScene` no longer reads `autoMode`. That reader IS the precedent #1071 \
            is argued from (#609: a swap must not silently change the look). If it was removed, \
            the beamer now strips Auto mode's visual half too — a second instance of the same \
            defect, not a simplification.
            """)
    }
}
