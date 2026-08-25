// TheInterfaceChannelCountIsHonestTests — pins #830, the pro-interface groundwork.
//
// FOUNDER ASK (2026-08-25): "Professionelle Audio Interface Integration." The #824
// audit's verdict: today an 8-in USB interface is SILENTLY truncated — the engine's
// input clamp takes at most two channels and the master graph is hard stereo — and
// no surface said so. #830 makes the truncation HONEST: `AudioInputInfo` carries the
// port's own channel count, and the picker row says "N inputs — Echoel uses the
// first two channels." on any device reporting more than two.
//
// Claim kinds per §1: test 1 is END-TO-END BEHAVIOUR (AudioInputInfo is a public
// Codable value type); tests 2–3 are SOURCE-TEXT SCANS. Whether iOS reports the
// true count for a given interface is a DEVICE PROBE and open.
//
// Deliberately NOT here (the lead plan's own gate): true multichannel stems and the
// mid-session hardware-format reconnect are Council-gated separate slices — this
// guard pins the honesty groundwork only and forbids neither (#364).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheInterfaceChannelCountIsHonestTests: XCTestCase {

    // MARK: - 1. Older payloads keep decoding (END-TO-END, the decodeIfPresent law)

    func testAPayloadWithoutTheCountDecodesToNilAndOneWithItRoundTrips() throws {
        // A pre-#830 payload has no `inputChannelCount` key — it must decode, to nil.
        let legacy = """
            {"id":"uid-1","name":"Studio Interface","portTypeRaw":"USBAudio",
             "kind":"usb","latency":"low"}
            """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AudioInputInfo.self, from: legacy)
        XCTAssertNil(decoded.inputChannelCount, """
            A payload without the key no longer decodes to nil — either the property \
            stopped being Optional (a missing key then THROWS and a stored list is \
            silently discarded, the try?-decode vaporization class) or a default is \
            invented, which conflates "the session did not say" with a measured value \
            (#654).
            """)
        // And a modern one round-trips the count.
        let modern = AudioInputInfo(id: "uid-2", name: "8-in Interface",
                                    portTypeRaw: "USBAudio", kind: .usb,
                                    latency: .low, inputChannelCount: 8)
        let round = try JSONDecoder().decode(AudioInputInfo.self,
                                             from: JSONEncoder().encode(modern))
        XCTAssertEqual(round.inputChannelCount, 8, "the count does not survive a round trip")
    }

    // MARK: - Source helpers

    private func code(_ repoRelative: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(repoRelative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(repoRelative) could not be read — fail, not skip (§4)")
            return ""
        }
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - 2. The count comes from the PORT and reaches the row (SOURCE SCAN)

    func testTheCountIsReadFromThePortAndRenderedOnlyPastTwo() {
        let manager = code("Sources/Echoelmusic/Audio/AudioInputManager.swift")
        let picker = code("Sources/Echoelmusic/Studio/AudioInputPickerView.swift")
        guard !manager.isEmpty, !picker.isEmpty else { return }
        XCTAssertTrue(manager.contains("inputChannelCount: port.channels?.count"), """
            refresh() no longer reads the channel count from the port description — \
            the field goes nil for every device and the honesty row can never render. \
            The count must be the HARDWARE's claim, never invented.
            """)
        XCTAssertTrue(picker.contains("channels > 2"), """
            The picker's gate is gone — either every mono/stereo device now gets a \
            pointless line, or no device gets one. The line exists for the case the \
            engine truncates: more than two reported inputs.
            """)
        XCTAssertTrue(picker.contains("first two channels"), """
            The row no longer states WHICH channels Echoel uses. "8 inputs" alone \
            reads as support; the honest half is the truncation.
            """)
    }

    // MARK: - 3. The premises that make the sentence TRUE (COUNTERWEIGHTS, #343)

    /// The row says "Echoel uses the first two channels" — that is only true while
    /// the engine actually clamps input to two and the master graph stays stereo.
    /// If either premise falls (a real multichannel slice lands), the ROW's copy
    /// must change in the same commit — this test names both sites.
    func testTheStereoTruncationPremisesStillHold() {
        let engine = code("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard !engine.isEmpty else { return }
        XCTAssertTrue(engine.contains("min(max(session.inputNumberOfChannels, 1), 2)"), """
            The engine's input clamp changed — if inputs beyond two are now used, the \
            picker row's "Echoel uses the first two channels." is FALSE and must be \
            updated in the same commit (#456). If the clamp merely moved or was \
            renamed, re-anchor this needle.
            """)
        XCTAssertTrue(engine.contains("min(outputFormat.channelCount, 2)"), """
            The master graph's stereo cap changed — same consequence as above: the \
            truncation sentence in AudioInputPickerView must move in the same commit.
            """)
    }
}
