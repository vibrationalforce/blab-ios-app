// TheHarmonyVoicesReachTheSingersDoorTests — pins #841 (V1b-2, first half).
//
// THE SLICE: the founder commissioned the vocal chain verbatim (2026-08-25,
// "latenzfrei… intelligenter Harmonizer und Granular Synthese Effekt Strategie…");
// #839 mounted the mic-owned chain NEUTRAL, #840 made its rate follow the bus.
// #841 gives the HARMONIZER its door: engine properties in the voiceTune shape
// (session-local, deliberately not persisted), a section in the existing input
// sheet (the sheet chain does NOT grow), and ONE preset-apply path into the insert
// that the #840 rate rebuild re-applies. DEFAULT OFF — the insert stays provably
// neutral until the singer flips the toggle. Granular has no audible stage on the
// voice yet (it needs its own slice; its `granularEnabled` stays off).
//
// KIND (§1): SOURCE-TEXT SCANS throughout (the door is `private` view code; the
// engine props live on a @MainActor @Observable the test host cannot drive
// meaningfully). Whether the harmony VOICES SOUND right on a real route is a
// DEVICE PROBE — open, answered by a founder take with the toggle on and the
// diag line `monitor: harmony on (…)`.
//
// GRADING (§3): claims 1–4 name symbols/text this same commit creates — on the
// parent they are red as ONE absence (#486), the #841 door not existing there.
// Claim 5 is the COUNTERWEIGHT, green on both trees where its needles exist:
// defaults stay off/neutral (the #839 all-off count lives in
// TheMonitorInsertCarriesTheNeutralChainTests and is not re-asserted here, #416).
// Driven in Python against parent and worktree before push.
//
// #364: nothing here forbids redesigning the door — a redesign re-anchors these
// claims in the same commit and pulls the prose homes claim 1's message names.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheHarmonyVoicesReachTheSingersDoorTests: XCTestCase {

    private func text(_ repoRelative: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(repoRelative)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(repoRelative) could not be read — fail, not skip (§4)")
            return ""
        }
        return SourceText.codeOnly(contents)
    }

    // MARK: - 1. ONE preset-apply path into the chain, called from door AND rebuild

    func testThePresetReachesTheChainThroughOneApplyPath() {
        let insert = text("Sources/Echoelmusic/Audio/MonitorInsertAU.swift")
        guard !insert.isEmpty else { return }
        XCTAssertEqual(insert.components(separatedBy: "private static func apply(").count - 1, 1, """
            The one preset-apply definition is gone or duplicated. Two spellings of \
            "preset reaches chain" is the #416 shape on the singer's own path — the \
            live door and the #840 rate rebuild MUST share one. If redesigned, \
            re-anchor here and pull: CLAUDE.md's vocal-chain line, \
            PLAN_VOCAL_CHAIN §6, the VoicePitchCorrector/EchoelGranular headers, \
            decisions.csv (#456).
            """)
        XCTAssertEqual(insert.components(separatedBy: "Self.apply(").count - 1, 2, """
            Expected exactly TWO apply call sites: the live door (applyVoicePreset) \
            and the #840 rate rebuild. One means a path stopped re-applying (a rate \
            swap would silently reset the singer's settings); three means a new \
            writer appeared outside the funnel.
            """)
        XCTAssertTrue(insert.contains("chain.harmonizerEnabled = preset.harmonizerEnabled"), """
            The apply body no longer writes the enable flag from the preset — the \
            toggle would stop reaching the stage.
            """)
    }

    // MARK: - 2. The rebuild applies BEFORE the box publishes the fresh chain

    func testTheRateRebuildAppliesThePresetBeforePublishing() {
        let insert = text("Sources/Echoelmusic/Audio/MonitorInsertAU.swift")
        guard !insert.isEmpty else { return }
        guard let apply = insert.range(of: "Self.apply(chainBox.preset, to: fresh)"),
              let publish = insert.range(of: "chainBox.replace(chain: fresh, sampleRate: negotiated)") else {
            return XCTFail("""
                The rebuild's apply-then-publish pair is gone from \
                allocateRenderResources. Without re-apply, a renegotiated route \
                resets the singer's harmony settings to neutral with no log line \
                saying so. If the rebuild moved, re-anchor this ordering (#456).
                """)
        }
        XCTAssertTrue(apply.lowerBound < publish.lowerBound, """
            The box publishes the fresh chain BEFORE the preset reaches it — a \
            render between the two lines would run the singer's monitor with his \
            settings dropped. Apply first, publish second.
            """)
    }

    // MARK: - 3. The engine door exists and funnels through the insert's API

    func testTheEngineDoorFunnelsIntoTheInsert() {
        let engine = text("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard !engine.isEmpty else { return }
        guard let fn = engine.range(of: "func setVoiceHarmony(") else {
            return XCTFail("""
                AudioEngine.setVoiceHarmony is gone — the sheet's toggle has no \
                setter. Re-anchor in the same commit (#456).
                """)
        }
        let body = String(engine[fn.lowerBound...].prefix(700))
        XCTAssertTrue(body.contains("guard on != voiceHarmonyEnabled else { return }"), """
            The idempotence guard is gone — every sheet redraw would re-log and \
            re-apply an unchanged state (the setVoiceTune shape this door copies).
            """)
        XCTAssertTrue(engine.contains("unit.applyVoicePreset(preset)"), """
            The engine no longer funnels through the insert's applyVoicePreset — a \
            second write path to the chain would bypass the stored preset and the \
            #840 rebuild would resurrect stale settings.
            """)
    }

    // MARK: - 4. The sheet's section: named intervals, numeric mix, availability gate

    func testTheDoorUsesNamedIntervalsAndANumericMix() {
        let sheet = text("Sources/Echoelmusic/Studio/AudioInputPickerView.swift")
        guard !sheet.isEmpty else { return }
        XCTAssertTrue(sheet.contains("if audioEngine.voiceHarmonyAvailable {"), """
            The availability gate is gone — when the insert factory fails, the \
            sheet would show a toggle over a stage with no host: an inert control, \
            the exact class the register calls worse than none.
            """)
        XCTAssertEqual(sheet.components(separatedBy: "ForEach(HarmonyInterval.allCases)").count - 1, 2, """
            Expected the TWO named-interval pickers. A harmony interval is a choice \
            with a NAME — the founder's "keine semitone Schritte" and the register's \
            "READ THE WORD NUMERIC" law; do not replace either with a number field.
            """)
        XCTAssertTrue(sheet.contains("audioEngine.setVoiceHarmony($0)"), """
            The toggle no longer routes through the engine's one setter — a direct \
            property write would skip the idempotence guard and the diag log line.
            """)
        XCTAssertTrue(sheet.contains("value: Binding(get: { audioEngine.voiceHarmonyMix },"), """
            The mix lost its EchoelValueField binding — mix IS numeric and follows \
            the one-control law.
            """)
    }

    // MARK: - 5. COUNTERWEIGHT: everything defaults OFF/neutral

    /// Green on both trees where the needles exist. The #839 neutral mount is only
    /// honest while the DOOR defaults off too — a default-on preset would flip the
    /// singer's monitor sound on update with no user action.
    func testTheDoorDefaultsOff() {
        let insert = text("Sources/Echoelmusic/Audio/MonitorInsertAU.swift")
        let engine = text("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard !insert.isEmpty, !engine.isEmpty else { return }
        XCTAssertTrue(insert.contains("public var harmonizerEnabled: Bool = false"), """
            MonitorVoicePreset's harmonizer default flipped on — the neutral-mount \
            law (#839) says every stage is off until the singer acts.
            """)
        XCTAssertTrue(engine.contains("private(set) var voiceHarmonyEnabled = false"), """
            The engine's harmony flag no longer defaults off (or lost its \
            private(set) — writes must go through setVoiceHarmony, which owns the \
            log line).
            """)
    }
}
