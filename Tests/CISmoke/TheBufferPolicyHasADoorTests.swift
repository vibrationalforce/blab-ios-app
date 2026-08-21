// TheBufferPolicyHasADoorTests.swift
// Echoel — the latency policy had no producer, and the obvious way to give it one would have
// re-shipped a device-diagnosed defect. #674.
//
// WHY THIS EXISTS. `AudioConfiguration.LatencyMode` describes three buffer tiers and
// `setLatencyMode` applies them. Measured 2026-08-21: `setLatencyMode` had ZERO callers in
// `Sources/`, so `currentBufferSize` never left `normalBufferSize` (512) whatever the session
// was doing. That is the Doctor §C shape — a mechanism that exists, reads as live in every
// file that mentions it, and nothing can select.
//
// ⛔ AND THE OBVIOUS FIX WAS A TRAP. "Monitoring is on, so drop the buffer" would have
// re-introduced 10.76.49: 256 frames was the shipped default until dense polyphonic chords
// missed the render deadline and the founder heard "Aussetzer / Kratzen" on the device. The
// declaration of `currentBufferSize` records it. A monitoring session on this app is usually
// the generative music PLUS the live voice — the dense case AND a monitor path — so an
// automatic switch would have aimed the regression at exactly the session it claimed to
// optimise. So the DEFAULT IS UNCHANGED and the choice is the player's, with the cost written
// beside it. Claim 1 is what stops a later session from "finishing the job".
//
// ⚠️ HONEST LIMITS. 5 test methods, 17 `XCTAssert*` — re-derive both, do not re-type:
//   grep -c "^    func test" <this file>
//   grep -n "XCTAssert" <this file> | grep -vc ':[[:space:]]*//'
// Claims 1–2 are EXECUTED BEHAVIOUR on shipped value types. Claims 3–5 are SOURCE-TEXT SCANS,
// because the view is `@MainActor` and `setLatencyMode` touches `AVAudioSession`.
// What NO test here can prove: that Low does not crackle on the founder's device under his
// material. That is the whole reason it is a choice with a warning and not a default.

import XCTest
@testable import Echoelmusic

final class TheBufferPolicyHasADoorTests: XCTestCase {

    private static let config = "Sources/Echoelmusic/Audio/AudioConfiguration.swift"
    private static let picker = "Sources/Echoelmusic/Studio/AudioInputPickerView.swift"

    // MARK: - 1. The default did not move

    func testTheShippedDefaultIsStillTheSafeBuffer() {
        XCTAssertEqual(AudioConfiguration.normalBufferSize,
                       AudioConfiguration.LatencyMode.normal.bufferSize, """
            `LatencyMode.normal` no longer names the shipped default buffer, so the segmented \
            control's "Normal" is no longer the size the app boots with — the one position a \
            player returns to when something crackles.
            """)
        XCTAssertLessThan(AudioConfiguration.LatencyMode.low.bufferSize,
                          AudioConfiguration.LatencyMode.normal.bufferSize,
                          "the tiers stopped being ordered smallest-to-largest by latency.")
        XCTAssertLessThan(AudioConfiguration.LatencyMode.ultraLow.bufferSize,
                          AudioConfiguration.LatencyMode.low.bufferSize,
                          "the tiers stopped being ordered smallest-to-largest by latency.")
    }

    // MARK: - 2. The mode is DERIVED from the buffer, never tracked beside it

    func testTheModeIsReadBackFromTheOneBufferValue() {
        // Whatever the size is right now, the derived mode must agree with it — or be `nil`,
        // which is the honest answer for a size no tier names.
        if let mode = AudioConfiguration.currentLatencyMode {
            XCTAssertEqual(mode.bufferSize, AudioConfiguration.currentBufferSize, """
                `currentLatencyMode` reports \(mode) while the buffer is \
                \(AudioConfiguration.currentBufferSize) frames. A mode tracked BESIDE the size \
                can disagree with it, and the size is what the measurement, the log line and \
                the on-screen floor all read — so the control would then be lying about a \
                number rendered two lines above it (#416).
                """)
        }
        XCTAssertEqual(AudioConfiguration.LatencyMode.allCases.count, 3,
                       "the tier list changed size; the segmented control's shape follows it.")
        // Distinct sizes, or two positions of the control would be the same setting.
        let sizes = Set(AudioConfiguration.LatencyMode.allCases.map(\.bufferSize))
        XCTAssertEqual(sizes.count, AudioConfiguration.LatencyMode.allCases.count, """
            Two tiers share a buffer size, so two positions of the segmented control do the \
            same thing and `currentLatencyMode` picks between them by declaration order.
            """)
        for mode in AudioConfiguration.LatencyMode.allCases {
            XCTAssertFalse(mode.shortName.isEmpty,
                           "a tier has no label, so one position of the control is blank.")
        }
    }

    // MARK: - 3. Nothing switches the buffer on its own

    func testTheBufferIsNeverChangedAutomatically() throws {
        let config = try Self.codeText(Self.config)
        let picker = try Self.codeText(Self.picker)

        // ⛔ This is the claim that matters. `setLatencyMode` may be called from a DOOR — a
        // control a person operates — and from nowhere else. An automatic call keyed off
        // monitoring, thermal state, or a route change would re-ship 10.76.49 at exactly the
        // session it claims to optimise, and it would do it silently: the crackle appears, the
        // player changed nothing, and no test goes red.
        let engine = try Self.codeText("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertEqual(Self.occurrences(of: "setLatencyMode", in: engine), 0, """
            `AudioEngine` now calls `setLatencyMode`. The buffer must not follow the engine's \
            state: 256 frames was the shipped default until dense chords missed the render \
            deadline and it was heard as crackle on the device (10.76.49). If this is a \
            deliberate decision, it needs the founder and a device probe, not a green test.
            """)
        XCTAssertEqual(Self.occurrences(of: "setLatencyMode", in: config), 1, """
            `setLatencyMode` is declared \(Self.occurrences(of: "setLatencyMode", in: config)) \
            times in its own file, expected exactly the declaration. A second spelling of "set \
            the buffer" can disagree with the first about whether the session is reconfigured.
            """)
        XCTAssertEqual(Self.occurrences(of: "setLatencyMode", in: picker), 1, """
            The picker calls `setLatencyMode` \(Self.occurrences(of: "setLatencyMode", in: picker)) \
            times, expected exactly once — from the control's own setter. A second call site in \
            a view is a call that is not a person pressing something.
            """)
    }

    // MARK: - 4. The cost is on screen, next to the switch

    func testTheSmallerBufferIsOfferedWithItsPrice() throws {
        let picker = try Self.codeText(Self.picker)

        XCTAssertTrue(picker.contains(".pickerStyle(.segmented)"), """
            The buffer control is no longer a segmented `Picker`. This is a NAMED choice of \
            three tiers, which the UI law routes to a `Picker` — the `EchoelValueField` rule \
            is for NUMERIC parameters, and offering 128–512 as a typed number would invite \
            sizes the audio graph never agreed to.
            """)
        // Source text, not the constant: `MonitorLatencyRow` is `private`, so `@testable`
        // does not reach it. The sibling guard pins its neighbour caveat the same way.
        XCTAssertTrue(picker.contains("crackled at Low before"), """
            The buffer caveat stopped naming the failure. 256 frames crackled on a real device \
            under dense chords (10.76.49); a switch whose failure mode is unstated hands the \
            player a mystery instead of a choice.
            """)
        XCTAssertTrue(picker.contains("Normal is the safe default"), """
            The caveat stopped naming the safe position, so a player who hears crackle has no \
            sentence telling them where to go back to.
            """)
    }

    // MARK: - 5. The freeze law: the control lives in the leaf it affects

    func testTheControlAndTheNumberItMovesShareOneLeaf() throws {
        let code = try Self.codeText(Self.picker)
        let leaf = try XCTUnwrap(code.range(of: "private struct MonitorLatencyRow: View"),
                                 "cannot anchor the leaf; re-anchor before trusting claim 5.")
        let above = String(code[code.startIndex..<leaf.lowerBound])
        XCTAssertTrue(above.contains("struct AudioInputPickerView"), """
            The leaf is declared BEFORE `AudioInputPickerView`, so the slice below is empty or \
            partial. Re-anchor on the parent's own body before trusting this claim (#454).
            """)
        XCTAssertEqual(Self.occurrences(of: "currentLatencyMode", in: above), 0, """
            The buffer mode is read ABOVE the leaf — inside `AudioInputPickerView` itself. \
            That body hosts Pickers, and a value read there registers the whole body as an \
            observer: every write tears down an open `.menu` popover (10.76.41/50). The \
            control sits in the leaf so the refresh stays local.
            """)
        XCTAssertEqual(Self.occurrences(of: "setLatencyMode", in: above), 0,
                       "the buffer is written from the parent body, not from the leaf's control.")
        XCTAssertFalse(code.contains("Timer.publish"), """
            The latency row acquired a POLL. The buffer changes only when someone presses the \
            control; a timer here rebuilds a view inside a Picker-hosting sheet on a schedule, \
            which is precisely the 10.76.41 freeze.
            """)
    }

    // MARK: - Helpers

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func codeText(_ path: String) throws -> String {
        SourceText.codeOnly(try repoText(path))
    }

    private static func repoText(_ path: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        throw NSError(domain: "TheBufferPolicyHasADoorTests", code: 1, userInfo:
                        [NSLocalizedDescriptionKey:
                          "cannot find \(path) walking up from #filePath — re-anchor (#454)."])
    }
}
