// TheGranularCloudReachesTheSingersDoorTests — pins #849 (V1b-3).
//
// THE SLICE: the founder commissioned harmonizer AND granular on his voice verbatim
// (2026-08-25); #841 doored the harmonizer, and this slice gives the GRANULAR stage
// the same-shaped door: engine properties in the voiceTune shape (session-local,
// deliberately not persisted), a section in the existing input sheet (the sheet
// chain does NOT grow), and the SHARED `pushVoicePreset()` into the insert's one
// apply path. DEFAULT OFF — the insert stays provably neutral until the singer
// flips the toggle.
//
// KIND (§1): SOURCE-TEXT SCANS throughout (the door is `private` view code; the
// engine props live on a @MainActor @Observable the test host cannot drive
// meaningfully). Whether the grain cloud SOUNDS right on a real route is a DEVICE
// PROBE — open, answered by a founder take with the toggle on and the diag line
// `monitor: granular on (…)`.
//
// GRADING (§3): claims 1–3 and the anti-clobber claim 5 name symbols/text this
// same commit creates — on the parent they are red as ONE absence (#486: the #849
// door and the renamed shared push do not exist there; the parent's push is
// `pushVoiceHarmony` and carries only harmony fields, which is exactly the clobber
// claim 5 forbids). Claim 4 is the COUNTERWEIGHT family: defaults stay off (its
// needles exist on the worktree only, so it too is red-by-absence on the parent —
// this file compiles there, it just finds nothing; ONE absence total). Driven in
// Python against parent and worktree before push.
//
// #364: nothing here forbids redesigning the door — a redesign re-anchors these
// claims in the same commit and pulls the prose homes the harmony guard's claim 1
// message names (they are shared between the two doors).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheGranularCloudReachesTheSingersDoorTests: XCTestCase {

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

    // MARK: - 1. The apply body writes granular parameters FIRST, the enable LAST

    func testTheApplyBodyWritesParametersBeforeTheEnable() {
        let insert = text("Sources/Echoelmusic/Audio/MonitorInsertAU.swift")
        guard !insert.isEmpty else { return }
        guard let mix = insert.range(of: "chain.granular.mix = preset.granularMix"),
              let enable = insert.range(of: "chain.granularEnabled = preset.granularEnabled") else {
            return XCTFail("""
                The granular half of the one apply body is gone. Without it the \
                sheet's toggle writes engine state that never reaches the chain — \
                an inert control. If the apply was redesigned, re-anchor here in \
                the same commit (#456).
                """)
        }
        XCTAssertTrue(mix.lowerBound < enable.lowerBound, """
            The enable is written before the parameters — `granularEnabled`'s \
            willSet resets the stage on the rising edge, so an enable-first order \
            would reset the stage BEFORE the final mix/grain/pitch arrive.
            """)
    }

    // MARK: - 2. The engine door exists, is idempotent, and funnels the shared push

    func testTheEngineDoorFunnelsTheSharedPush() {
        let engine = text("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard !engine.isEmpty else { return }
        guard let fn = engine.range(of: "func setVoiceGranular(") else {
            return XCTFail("""
                AudioEngine.setVoiceGranular is gone — the sheet's toggle has no \
                setter. Re-anchor in the same commit (#456).
                """)
        }
        let body = String(engine[fn.lowerBound...].prefix(700))
        XCTAssertTrue(body.contains("guard on != voiceGranularEnabled else { return }"), """
            The idempotence guard is gone — every sheet redraw would re-log and \
            re-apply an unchanged state (the setVoiceTune/setVoiceHarmony shape \
            this door copies).
            """)
        XCTAssertTrue(body.contains("pushVoicePreset()"), """
            The granular setter no longer funnels through the shared push — a \
            direct write path would bypass the stored preset and the #840 rate \
            rebuild would resurrect stale settings.
            """)
    }

    // MARK: - 3. The sheet's section routes through the setter, numeric fields

    func testTheSheetSectionRoutesThroughTheSetter() {
        let sheet = text("Sources/Echoelmusic/Studio/AudioInputPickerView.swift")
        guard !sheet.isEmpty else { return }
        XCTAssertTrue(sheet.contains("audioEngine.setVoiceGranular($0)"), """
            The toggle no longer routes through the engine's one setter — a direct \
            property write would skip the idempotence guard and the diag log line.
            """)
        XCTAssertTrue(sheet.contains("value: Binding(get: { audioEngine.voiceGranularMix },"), """
            The mix lost its EchoelValueField binding — every granular parameter \
            here is genuinely numeric and follows the one-control law.
            """)
    }

    // MARK: - 4. COUNTERWEIGHT: everything defaults OFF

    /// The #839 neutral mount is only honest while BOTH doors default off — a
    /// default-on preset would flip the singer's monitor sound on update with no
    /// user action.
    func testTheDoorDefaultsOff() {
        let insert = text("Sources/Echoelmusic/Audio/MonitorInsertAU.swift")
        let engine = text("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard !insert.isEmpty, !engine.isEmpty else { return }
        XCTAssertTrue(insert.contains("public var granularEnabled: Bool = false"), """
            MonitorVoicePreset's granular default flipped on — the neutral-mount \
            law (#839) says every stage is off until the singer acts.
            """)
        XCTAssertTrue(engine.contains("private(set) var voiceGranularEnabled = false"), """
            The engine's granular flag no longer defaults off (or lost its \
            private(set) — writes must go through setVoiceGranular, which owns \
            the log line).
            """)
    }

    // MARK: - 5. The anti-clobber law: ONE push carries BOTH stages

    /// The reason the push is shared: a push that rebuilt the preset from only one
    /// stage's fields would silently reset the OTHER stage on every unrelated edit
    /// (toggling harmony would mute an enabled granular, and vice versa).
    func testOnePushCarriesBothStages() {
        let engine = text("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard !engine.isEmpty else { return }
        XCTAssertEqual(engine.components(separatedBy: "private func pushVoicePreset()").count - 1, 1, """
            The shared push definition is gone or duplicated — two pushes with \
            partial field sets is exactly the clobber this test forbids.
            """)
        guard let fn = engine.range(of: "private func pushVoicePreset()") else { return }
        let body = String(engine[fn.lowerBound...].prefix(1400))
        XCTAssertTrue(body.contains("preset.harmonizerEnabled = voiceHarmonyEnabled"), """
            The shared push stopped carrying the HARMONY enable — toggling \
            granular would now silently switch the harmony voices off.
            """)
        XCTAssertTrue(body.contains("preset.granularEnabled = voiceGranularEnabled"), """
            The shared push stopped carrying the GRANULAR enable — toggling \
            harmony would now silently switch the grain cloud off.
            """)
    }
}
