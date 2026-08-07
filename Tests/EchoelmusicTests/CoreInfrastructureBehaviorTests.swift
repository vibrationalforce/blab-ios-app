#if canImport(AVFoundation)
// CoreInfrastructureBehaviorTests.swift
// Echoelmusic — Behavioral tests for core infrastructure: CrashSafeStatePersistence.
// (The UndoRedoManager tests were removed 2026-07-21: that singleton no longer
//  exists — undo/redo now lives in TimelineStore + PianoRollModel. The second name read
//  `PianoRollView` until #475 deleted that struct; the undo stack was always the MODEL's.)

import XCTest
@testable import Echoelmusic

// MARK: - CrashSafeStatePersistence Behavior Tests

@MainActor
final class CrashSafeStatePersistenceBehaviorTests: XCTestCase {

    // MARK: - SessionState Construction

    func testSessionState_DefaultInit_HasValidDefaults() {
        let state = SessionState()
        XCTAssertNotEqual(state.sessionId, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        XCTAssertEqual(state.durationSeconds, 0)
        XCTAssertNil(state.activePreset)
        XCTAssertTrue(state.bioSettings.enabled)
        XCTAssertEqual(state.audioSettings.volume, 0.8, accuracy: 0.01)
        XCTAssertEqual(state.audioSettings.bpm, 120, accuracy: 0.01)
        XCTAssertTrue(state.userData.isEmpty)
    }

    func testSessionState_Codable_RoundTrips() throws {
        var state = SessionState()
        state.activePreset = "Meditation"
        state.audioSettings.volume = 0.6
        state.bioSettings.coherenceThreshold = 0.75
        state.userData["testKey"] = "testValue"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionState.self, from: data)

        XCTAssertEqual(decoded.sessionId, state.sessionId)
        XCTAssertEqual(decoded.activePreset, "Meditation")
        XCTAssertEqual(decoded.audioSettings.volume, 0.6, accuracy: 0.01)
        XCTAssertEqual(decoded.bioSettings.coherenceThreshold, 0.75, accuracy: 0.01)
        XCTAssertEqual(decoded.userData["testKey"], "testValue")
    }

    func testSessionState_CorruptData_FailsGracefully() {
        let corrupt = Data("not valid json at all".utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = try? decoder.decode(SessionState.self, from: corrupt)
        XCTAssertNil(result, "Corrupt data should not decode")
    }

    func testSessionState_EmptyJSON_FailsGracefully() {
        let emptyJSON = Data("{}".utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = try? decoder.decode(SessionState.self, from: emptyJSON)
        XCTAssertNil(result, "Incomplete JSON should not decode")
    }

    // MARK: - SessionStateBuilder

    func testSessionStateBuilder_BuildsWithPreset() {
        let state = SessionStateBuilder()
            .withPreset("Focus")
            .build()
        XCTAssertEqual(state.activePreset, "Focus")
    }

    func testSessionStateBuilder_BuildsWithAudioSettings() {
        let state = SessionStateBuilder()
            .withAudioSettings(volume: 0.5, bpm: 140)
            .build()
        XCTAssertEqual(state.audioSettings.volume, 0.5, accuracy: 0.01)
        XCTAssertEqual(state.audioSettings.bpm, 140, accuracy: 0.01)
    }

    func testSessionStateBuilder_CoherenceReading_UpdatesMetrics() {
        let state = SessionStateBuilder()
            .withCoherenceReading(0.8)
            .withCoherenceReading(0.6)
            .build()
        XCTAssertEqual(state.metrics.coherenceReadings, 2)
        XCTAssertEqual(state.metrics.peakCoherence, 0.8, accuracy: 0.01)
        // Average should be (0.8 + 0.6) / 2 = 0.7 via running average
        XCTAssertEqual(state.metrics.averageCoherence, 0.7, accuracy: 0.01)
    }

    func testSessionStateBuilder_UserData_Stored() {
        let state = SessionStateBuilder()
            .withUserData("theme", value: "dark")
            .build()
        XCTAssertEqual(state.userData["theme"], "dark")
    }

    func testSessionStateBuilder_ChainedCalls_ProducesValidState() {
        let state = SessionStateBuilder()
            .withPreset("Live")
            .withAudioSettings(volume: 0.9, bpm: 128)
            .withBioSettings(enabled: true, coherenceThreshold: 0.5)
            .withCoherenceReading(0.85)
            .withUserData("mode", value: "performance")
            .build()

        XCTAssertEqual(state.activePreset, "Live")
        XCTAssertEqual(state.audioSettings.volume, 0.9, accuracy: 0.01)
        XCTAssertEqual(state.audioSettings.bpm, 128, accuracy: 0.01)
        XCTAssertTrue(state.bioSettings.enabled)
        XCTAssertEqual(state.bioSettings.coherenceThreshold, 0.5, accuracy: 0.01)
        XCTAssertEqual(state.metrics.peakCoherence, 0.85, accuracy: 0.01)
        XCTAssertEqual(state.userData["mode"], "performance")
    }

    // MARK: - CrashSafeStatePersistence Singleton

    func testCrashSafeStatePersistence_SharedInstance_Exists() {
        let persistence = CrashSafeStatePersistence.shared
        XCTAssertNotNil(persistence, "Shared instance must exist")
    }

    func testCrashSafeStatePersistence_ClearAllState_ResetsPendingRecovery() {
        let persistence = CrashSafeStatePersistence.shared
        persistence.clearAllState()
        XCTAssertFalse(persistence.hasPendingRecovery, "No recovery after clearing")
    }

    func testCrashSafeStatePersistence_DismissRecovery_ClearsPendingFlag() {
        let persistence = CrashSafeStatePersistence.shared
        persistence.dismissRecovery()
        XCTAssertFalse(persistence.hasPendingRecovery)
    }
}

#endif
