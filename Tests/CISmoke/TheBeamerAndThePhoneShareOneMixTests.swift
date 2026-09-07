import XCTest
@testable import Echoelmusic

/// #1073 — THE BEAMER DRAWS THE PHONE'S PICTURE. This file replaces
/// `TheBeamerDrawsTheSamePictureTests`, which pinned the GAP and instructed its own deletion
/// in the commit that closed it.
///
/// THE HISTORY IN ONE PARAGRAPH, because the shape recurs and the fix does not explain it:
/// from #594 until #1071 the two rendering surfaces shared the KEYS and not the PICTURE. The
/// phone mixed the live weather into hue · saturation · intensity · motion, each behind its
/// own user mixer; `ExternalStageView` read the same four `@AppStorage` keys and handed them
/// to `MetalBioView` raw. Plugging in a projector silently dropped the tint mid-show, the
/// prose at both sites read as if they matched, and nothing could see it without a projector.
/// #1071 measured it, #1072 gave the mix ONE definition, #1073 wired the consumer.
///
/// ⚠️ SOURCE-TEXT SCAN (§1), and it is the right strength here: the ARITHMETIC is already
/// driven end-to-end by `TheWeatherVisualMixHasOneDefinitionTests`. What can still rot is the
/// WIRING — a surface quietly going back to the raw key — and wiring is what this file holds.
/// Whether a projector looks right stays a DEVICE PROBE.
final class TheBeamerAndThePhoneShareOneMixTests: XCTestCase {

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
    private static let bridge = "Sources/Echoelmusic/Studio/ExternalStageBridge.swift"

    // 1 — BOTH surfaces call the ONE definition, and NEITHER re-derives it. The second half is
    // the load-bearing one: a copy would agree on the day it was written and drift after.
    func testBothSurfacesCallTheSharedMix() throws {
        for path in [Self.window, Self.scene] {
            let code = try source(path)
            XCTAssertTrue(code.contains("WeatherMood.visualValues("), """
                \(path) no longer calls the shared weather mix. If that surface was meant to \
                render RAW again, that is a founder-visible change to what a projector shows \
                and needs its own commit — do not let it arrive inside a refactor.
                """)
            XCTAssertFalse(code.contains("WeatherMood.blend(base:"), """
                \(path) crossfades the sky itself again instead of calling the shared \
                definition. Two spellings of one decision is exactly what produced #1071, and \
                a copy looks correct for as long as nobody changes either one.
                """)
        }
    }

    // 2 — THE SCENE ACTUALLY RENDERS THE MIXED VALUES. Claim 1 would pass over a scene that
    // computed `wx` and then handed `MetalBioView` the raw keys anyway — which is precisely
    // the bug in its most likely re-entry form, since the raw properties still exist.
    func testTheSceneRendersTheMixedValuesAndNotTheRawKeys() throws {
        let code = try source(Self.scene)
        for arg in ["intensity: Float(wx.intensity)",
                    "motion: Float(wx.motion)",
                    "hueShift: Float(wx.hue)",
                    "saturation: Float(wx.saturation)"] {
            XCTAssertTrue(code.contains(arg), """
                `\(arg)` is gone from the external `MetalBioView` call. The four raw \
                `@AppStorage` properties are still in scope, so dropping back to one of them \
                compiles cleanly and shows up only on a projector. Re-anchor here if the \
                argument was renamed.
                """)
        }
    }

    // 3 — COUNTERWEIGHT (#367): the sky really CROSSES. Without the bridge member and its
    // publisher, claims 1 and 2 pass over a scene that mixes a permanently-nil contribution —
    // i.e. renders exactly the raw picture it did before, through a longer path.
    func testTheSkyReallyCrossesToTheScene() throws {
        let bridgeCode = try source(Self.bridge)
        XCTAssertTrue(bridgeCode.contains("var sky: WeatherMood.Contribution?"), """
            `ExternalStageBridge` no longer carries the sky. That is the ONLY route: the \
            external hierarchy is built by UIKit and inherits no `@Environment`, and \
            `WeatherSnapshot` is never persisted, so there is nothing for the scene to read \
            back on its own.
            """)
        XCTAssertTrue(bridgeCode.contains("func setSky("), "the bridge has no sky writer.")
        let windowCode = try source(Self.window)
        XCTAssertTrue(windowCode.contains("ExternalStageBridge.shared.setSky("), """
            Nothing publishes the sky any more, so the beamer would mix a nil contribution and \
            render the raw picture again — the #1071 defect restored, silently, through code \
            that still looks wired.
            """)
        XCTAssertTrue(windowCode.contains("initial: true"), """
            The sky is published only on CHANGE. The normal stage order is "projector already \
            plugged in", and on a 30-minute weather cache the first change can be the whole \
            show — so the beamer would run untinted for it.
            """)
    }

    // 4 — ⭐ THE DIVERGENCE ONE LEVEL DOWN, which is the mistake this slice was most likely to
    // make while repairing the first one. The scene's mixer defaults must be the same
    // EXPRESSION the window uses, never a copy of its value: literals agree on the day they
    // are written and stop agreeing the day `defaultIntensity` changes.
    func testTheMixerDefaultsAreTheSameExpressionOnBothSurfaces() throws {
        let windowCode = try source(Self.window)
        let sceneCode = try source(Self.scene)
        for param in ["hue", "saturation", "glow", "movement"] {
            let needle = "WeatherMood.Param.\(param).defaultIntensity"
            XCTAssertTrue(windowCode.contains(needle),
                          "the window stopped using \(needle) — re-anchor both halves together.")
            XCTAssertTrue(sceneCode.contains(needle), """
                The beamer's `\(param)` mixer default is not \(needle) any more. If it became a \
                literal, the two surfaces agree today and diverge the moment that default \
                changes — the same defect as #1071, one level down and even harder to see.
                """)
        }
    }
}
