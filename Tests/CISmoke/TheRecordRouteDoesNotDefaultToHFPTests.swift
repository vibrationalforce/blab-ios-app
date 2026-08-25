// TheRecordRouteDoesNotDefaultToHFPTests — pins the #824 Bluetooth-quality repair.
//
// THE FAILURE THIS GUARDS (founder, 2026-08-25: "Mit Bluetooth Kopfhörer/headset
// komischen gesamt Klang vermeiden"): `recordOptions` carried `.allowBluetooth`
// (HFP) unconditionally, so the moment any mic feature claimed the route, iOS
// could move a dual-profile Bluetooth headset onto the 8/16 kHz mono call codec —
// MUSIC included. #824 makes HFP an OPT-IN: the default record set is A2DP-only
// (full-quality stereo out, mic from iPhone/wired/USB), and `.allowBluetooth` is
// added only behind the persisted `audio.bluetoothHFPMic` flag, whose one door is
// the "Bluetooth headset mic" toggle in `AudioInputPickerView`.
//
// All claims are source scans (Bluetooth routing does not exist in any simulator;
// the routing outcome itself is a device-only fact and sits in the founder-verify
// queue). #364: this guard does not forbid future work — if the mechanism is
// deliberately redesigned, re-anchor these claims in the same commit and pull the
// prose homes its messages name (#456): AudioConfiguration's recordOptions doc,
// the routeCodec doc, TheBluetoothCodecReachesTheScreenTests' header, and the
// SESSION_LOG #824 entry.

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

    func testTheDefaultRecordOptionsCarryNoHFP() {
        let config = source("Sources/Echoelmusic/Audio/AudioConfiguration.swift")
        guard !config.isEmpty else { return }
        guard let start = config.range(of: "private static var recordOptions") else {
            XCTFail("recordOptions is no longer a computed var in AudioConfiguration — "
                    + "#824 made it computed so HFP can be opt-in. If it was renamed or "
                    + "redesigned, re-anchor this guard in the same commit.")
            return
        }
        let window = String(config[start.lowerBound...].prefix(500))
        // The base set must be A2DP-only. `.allowBluetoothA2DP` CONTAINS
        // `.allowBluetooth` as a substring, so strip the A2DP spelling first —
        // a naive needle here could never fail (#808) or never pass.
        guard let baseLineRange = window.range(of: "var options: AVAudioSession.CategoryOptions") else {
            XCTFail("The recordOptions base-set line moved — re-anchor this guard.")
            return
        }
        let base = String(window[baseLineRange.lowerBound...].prefix(140))
        let baseWithoutA2DP = base.replacingOccurrences(of: ".allowBluetoothA2DP", with: "")
        XCTAssertTrue(base.contains(".allowBluetoothA2DP"),
                      "The default record set lost .allowBluetoothA2DP — Bluetooth "
                      + "OUTPUT (the good codec) must stay allowed. Base line: \(base)")
        XCTAssertFalse(baseWithoutA2DP.contains(".allowBluetooth"),
                       "#824 is undone: .allowBluetooth (HFP) is back in the DEFAULT "
                       + "record set. That lets iOS pull a Bluetooth headset — music "
                       + "included — onto the mono call codec whenever the mic route is "
                       + "claimed: the founder's 'komischer Gesamtklang'. HFP must stay "
                       + "behind the bluetoothHFPMicEnabled opt-in. Base line: \(base)")
        XCTAssertTrue(window.contains("if bluetoothHFPMicEnabled")
                      && window.contains("insert(.allowBluetooth)"),
                      "The HFP opt-in gate is gone from recordOptions — either the flag "
                      + "no longer feeds the option set (the toggle becomes a lie) or the "
                      + "mechanism was redesigned without re-anchoring this guard.")
    }

    func testTheFlagHasExactlyOneKeyDefinitionAndAReachableDoor() {
        let config = source("Sources/Echoelmusic/Audio/AudioConfiguration.swift")
        let picker = source("Sources/Echoelmusic/Studio/AudioInputPickerView.swift")
        guard !config.isEmpty, !picker.isEmpty else { return }
        // ONE definition of the key literal (#416) — the door must reference the
        // constant, never re-type the string.
        let literal = "\"audio.bluetoothHFPMic\""
        let inConfig = config.components(separatedBy: literal).count - 1
        let inPicker = picker.components(separatedBy: literal).count - 1
        XCTAssertEqual(inConfig, 1,
                       "The key literal must appear exactly once, in AudioConfiguration "
                       + "(found \(inConfig)) — a second spelling is the two-owners drift "
                       + "this repo keeps paying for (#416).")
        XCTAssertEqual(inPicker, 0,
                       "AudioInputPickerView re-types the key literal (found \(inPicker)) "
                       + "instead of using AudioConfiguration.bluetoothHFPMicKey.")
        // The door: an @AppStorage on the shared constant, honest copy, and the
        // live re-apply so the choice takes effect mid-monitoring.
        XCTAssertTrue(picker.contains("@AppStorage(AudioConfiguration.bluetoothHFPMicKey)"),
                      "The HFP opt-in lost its door — a persisted flag nothing can set is "
                      + "the doorless-state defect (#204/#713): the reader would resolve "
                      + "false forever and the capability silently vanishes.")
        XCTAssertTrue(picker.contains("call quality"),
                      "The toggle's copy no longer states the trade-off (call quality). "
                      + "An opt-in into degraded sound without saying so is the overclaim "
                      + "class in reverse — the user must choose knowingly.")
        XCTAssertTrue(picker.contains("reapplyRecordRouteForHFPChoice()"),
                      "The toggle no longer re-applies the record route — flipping it "
                      + "mid-monitoring would silently do nothing until the next claim.")
    }
}
