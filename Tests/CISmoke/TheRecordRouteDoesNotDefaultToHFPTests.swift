// TheRecordRouteDoesNotDefaultToHFPTests — pins the HFP ban (#824 → #827).
//
// HISTORY, because this guard changed shape within one day and the reason is a
// FOUNDER DECISION, not a redesign: #824 removed `.allowBluetooth` (HFP) from the
// default record options and put it behind a persisted opt-in toggle ("Bluetooth
// headset mic"). The founder struck the opt-in the same day — verbatim: "Keine
// Telefonqualität zulassen, das mag niemand" — so #827 deleted the toggle, its
// key and the live re-apply helper outright. Echoel NEVER requests HFP: with it,
// iOS may move a dual-profile Bluetooth headset onto the 8/16 kHz mono call
// codec the moment the mic route is claimed, music included (the "komischer
// Gesamtklang", 2026-08-25). The headset's own mic is simply never used.
//
// SOURCE-TEXT SCANS (§1) — Bluetooth routing exists in no simulator; the routing
// outcome is a device fact in the founder-verify queue. Comment lines are
// stripped before every needle: the retraction docs QUOTE the banned token and
// the deleted key on purpose (#491), and a scan that read prose would hit its
// own history.
//
// #364 note: this guard DOES forbid re-adding HFP — deliberately, because it
// enforces an explicit founder decision, which is the one thing a guard may pin
// hard. If the founder ever reverses it, update this file, the recordOptions
// doc, the routeCodec doc and the SESSION_LOG in the same commit (#456).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheRecordRouteDoesNotDefaultToHFPTests: XCTestCase {

    private func source(_ repoRelative: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(repoRelative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(repoRelative) could not be read — fail, not skip (§4)")
            return ""
        }
        return text
    }

    /// Comment lines removed — the ⛔ retraction blocks quote the banned token
    /// and the deleted key deliberately (#491).
    private func code(_ repoRelative: String) -> String {
        source(repoRelative)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testEchoelNeverRequestsHFP() {
        let config = code("Sources/Echoelmusic/Audio/AudioConfiguration.swift")
        guard !config.isEmpty else { return }
        // `.allowBluetoothA2DP` CONTAINS `.allowBluetooth` as a substring — strip
        // the A2DP spelling first, or this needle could never fail (#808) or
        // never pass.
        let a2dpCount = config.components(separatedBy: ".allowBluetoothA2DP").count - 1
        let withoutA2DP = config.replacingOccurrences(of: ".allowBluetoothA2DP", with: "")
        // Anti-vacuous: the file must still configure Bluetooth OUTPUT at its
        // three sites (playback set, record set, downgrade set). Zero here means
        // an anchor moved, not a clean file.
        XCTAssertGreaterThanOrEqual(a2dpCount, 3, """
            Fewer than three .allowBluetoothA2DP sites in AudioConfiguration — \
            Bluetooth OUTPUT (the good stereo codec) must stay allowed on the \
            playback, record and downgrade option sets. If a set was legitimately \
            restructured, re-anchor this count in the same commit.
            """)
        XCTAssertFalse(withoutA2DP.contains(".allowBluetooth"), """
            `.allowBluetooth` (HFP) is back in AudioConfiguration's CODE. The \
            founder banned telephone quality outright (#827, "Keine Telefonqualität \
            zulassen, das mag niemand" — it was an opt-in for exactly one cycle, \
            #824). With HFP requested, iOS may pull the WHOLE shared route — music \
            included — onto the 8/16 kHz mono call codec. If the founder reverses \
            this decision, update this guard, the recordOptions doc, the routeCodec \
            doc and the SESSION_LOG in the same commit (#456).
            """)
    }

    func testTheStruckOptInLeavesNoResidue() {
        let config = code("Sources/Echoelmusic/Audio/AudioConfiguration.swift")
        let picker = code("Sources/Echoelmusic/Studio/AudioInputPickerView.swift")
        guard !config.isEmpty, !picker.isEmpty else { return }
        for needle in ["\"audio.bluetoothHFPMic\"", "bluetoothHFPMicEnabled",
                       "reapplyRecordRouteForHFPChoice"] {
            XCTAssertFalse(config.contains(needle) || picker.contains(needle), """
                A piece of the struck #824 HFP opt-in is back in code: \(needle). \
                The founder deleted the capability, not just its default (#827) — \
                a surviving reader or key invites the next session to re-door it \
                (the doorless-state trap in reverse).
                """)
        }
        XCTAssertFalse(picker.contains("Text(\"Bluetooth headset mic\")"), """
            The "Bluetooth headset mic" toggle is back in the Input sheet. The \
            founder struck it the same day it shipped (#827): there is no world \
            with both the headset's own mic and full-quality music on one \
            Bluetooth link, and the founder chose the music for everyone.
            """)
    }
}
