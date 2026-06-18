// AudioInputManagerTests.swift
// Echoel — the input classifier must label every route honestly, especially the
// Bluetooth latency wall, so the UI can warn before a performer relies on a route
// that can't monitor in real time. Pure + cross-platform → tested everywhere.

import XCTest
@testable import Echoelmusic

final class AudioInputManagerTests: XCTestCase {

    func testBuiltInMic_isLowLatency() {
        let c = AudioInputClassifier.classify(portTypeRaw: "MicrophoneBuiltIn")
        XCTAssertEqual(c.kind, .builtIn)
        XCTAssertEqual(c.latency, .low)
    }

    func testWiredHeadset_isLowLatency() {
        XCTAssertEqual(AudioInputClassifier.classify(portTypeRaw: "HeadsetMicrophone").kind, .wired)
        XCTAssertEqual(AudioInputClassifier.classify(portTypeRaw: "LineIn").latency, .low)
    }

    func testUSBInterface_isLowLatency() {
        let c = AudioInputClassifier.classify(portTypeRaw: "USBAudio")
        XCTAssertEqual(c.kind, .usb)
        XCTAssertEqual(c.latency, .low)
    }

    func testBluetooth_allProfiles_areHighLatency() {
        for raw in ["BluetoothHFP", "BluetoothA2DPOutput", "BluetoothLE"] {
            let c = AudioInputClassifier.classify(portTypeRaw: raw)
            XCTAssertEqual(c.kind, .bluetooth, "\(raw) is bluetooth")
            XCTAssertEqual(c.latency, .high, "\(raw) is high latency — the honest BT wall")
        }
    }

    func testCarAudio_isHighLatency() {
        XCTAssertEqual(AudioInputClassifier.classify(portTypeRaw: "CarAudio").kind, .carPlay)
        XCTAssertEqual(AudioInputClassifier.classify(portTypeRaw: "CarAudio").latency, .high)
    }

    func testUnknownPort_fallsBackBySubstring() {
        XCTAssertEqual(AudioInputClassifier.classify(portTypeRaw: "SomeBluetoothThing").kind, .bluetooth)
        XCTAssertEqual(AudioInputClassifier.classify(portTypeRaw: "MysteryUSBDock").kind, .usb)
        XCTAssertEqual(AudioInputClassifier.classify(portTypeRaw: "TotallyUnknown").kind, .other)
        XCTAssertEqual(AudioInputClassifier.classify(portTypeRaw: "TotallyUnknown").latency, .medium)
    }

    func testLatencyAdvice_isNonEmptyAndHonestForBluetooth() {
        XCTAssertTrue(MonitoringLatency.high.advice.lowercased().contains("wired"),
                      "high-latency advice points the user to a wired monitor path")
        for l in MonitoringLatency.allCases {
            XCTAssertFalse(l.advice.isEmpty)
        }
    }

    func testInfo_isCodableRoundTrip() throws {
        let info = AudioInputInfo(id: "uid-1", name: "Studio Interface",
                                  portTypeRaw: "USBAudio", kind: .usb, latency: .low)
        let data = try JSONEncoder().encode(info)
        let back = try JSONDecoder().decode(AudioInputInfo.self, from: data)
        XCTAssertEqual(back, info)
    }
}
