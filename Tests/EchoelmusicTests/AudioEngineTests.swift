#if canImport(AVFoundation)
// AudioEngineTests.swift
// Echoelmusic — Phase 2 Test Coverage: Infrastructure Tests
//
// Tests for MemoryPressureLevel, LogLevel, LogCategory, LogEntry,
// SessionState.BioSettings/AudioSettings, and EchoelLogger.
// (The Metronome*/CountInMode/TunerReading/MusicalNote-extended/
//  TuningReference-extended tests were removed 2026-07-21 — those types were
//  redesigned/removed: MetronomeVoice replaced the old metronome value types,
//  MusicalNote is now a {frequencyHz, amplitude} chord note, and TuningReference
//  is a struct with a4Hz. The tests exercised API that no longer exists.)

import XCTest
@testable import Echoelmusic

// MARK: - MemoryPressureLevel Tests

final class MemoryPressureLevelTests: XCTestCase {

    func testComparable() {
        XCTAssertTrue(MemoryPressureLevel.normal < .warning)
        XCTAssertTrue(MemoryPressureLevel.warning < .critical)
        XCTAssertTrue(MemoryPressureLevel.critical < .terminal)
    }

    func testDescription() {
        XCTAssertEqual(MemoryPressureLevel.normal.description, "Normal")
        XCTAssertEqual(MemoryPressureLevel.warning.description, "Warning")
        XCTAssertEqual(MemoryPressureLevel.critical.description, "Critical")
        XCTAssertEqual(MemoryPressureLevel.terminal.description, "Terminal")
    }

    func testRawValues() {
        XCTAssertEqual(MemoryPressureLevel.normal.rawValue, 0)
        XCTAssertEqual(MemoryPressureLevel.warning.rawValue, 1)
        XCTAssertEqual(MemoryPressureLevel.critical.rawValue, 2)
        XCTAssertEqual(MemoryPressureLevel.terminal.rawValue, 3)
    }
}

// MARK: - LogLevel Tests

final class LogLevelTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(LogLevel.allCases.count, 7)
    }

    func testComparable() {
        XCTAssertTrue(LogLevel.trace < .debug)
        XCTAssertTrue(LogLevel.debug < .info)
        XCTAssertTrue(LogLevel.info < .notice)
        XCTAssertTrue(LogLevel.notice < .warning)
        XCTAssertTrue(LogLevel.warning < .error)
        XCTAssertTrue(LogLevel.error < .critical)
    }

    func testEmoji() {
        for level in LogLevel.allCases {
            XCTAssertFalse(level.emoji.isEmpty, "\(level) should have emoji")
        }
    }

    func testRawValuesAscending() {
        let allCases = LogLevel.allCases
        for i in 1..<allCases.count {
            XCTAssertGreaterThan(allCases[i].rawValue, allCases[i - 1].rawValue)
        }
    }

    func testOsLogType() {
        for level in LogLevel.allCases {
            let osType = level.osLogType
            XCTAssertNotNil(osType, "osLogType should be valid for \(level)")
        }
    }
}

// MARK: - LogCategory Tests

final class LogCategoryTests: XCTestCase {

    func testCoreCategories() {
        let categories = LogCategory.allCases.map { $0.rawValue }
        XCTAssertTrue(categories.contains("Audio"))
        XCTAssertTrue(categories.contains("Video"))
        XCTAssertTrue(categories.contains("MIDI"))
        XCTAssertTrue(categories.contains("Biofeedback"))
        XCTAssertTrue(categories.contains("System"))
        XCTAssertTrue(categories.contains("UI"))
        XCTAssertTrue(categories.contains("Performance"))
        XCTAssertTrue(categories.contains("Network"))
    }

    func testOsLog() {
        for category in LogCategory.allCases {
            let osLog = category.osLog
            XCTAssertNotNil(osLog)
        }
    }

    func testTotalCount() {
        // 30 categories defined in ProfessionalLogger.swift
        XCTAssertEqual(LogCategory.allCases.count, 30)
    }
}

// MARK: - LogEntry Tests

final class LogEntryTests: XCTestCase {

    func testFormattedMessage() {
        let entry = LogEntry(
            level: .info,
            category: .audio,
            message: "Test message",
            file: "/path/to/TestFile.swift",
            function: "testFunc",
            line: 42
        )
        let formatted = entry.formattedMessage
        XCTAssertTrue(formatted.contains("Audio"))
        XCTAssertTrue(formatted.contains("Test message"))
        XCTAssertTrue(formatted.contains("TestFile.swift"))
        XCTAssertTrue(formatted.contains("42"))
    }

    func testMetadata() {
        let entry = LogEntry(
            level: .debug,
            category: .system,
            message: "Debug",
            file: "test.swift",
            function: "test",
            line: 1,
            metadata: ["key": "value"]
        )
        XCTAssertEqual(entry.metadata["key"], "value")
    }

    func testUniqueIds() {
        let entry1 = LogEntry(level: .info, category: .audio, message: "a", file: "", function: "", line: 0)
        let entry2 = LogEntry(level: .info, category: .audio, message: "b", file: "", function: "", line: 0)
        XCTAssertNotEqual(entry1.id, entry2.id)
    }

    func testTimestamp() {
        let before = Date()
        let entry = LogEntry(level: .info, category: .system, message: "t", file: "", function: "", line: 0)
        let after = Date()
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }
}

// MARK: - SessionState.BioSettings Tests

final class SessionStateBioSettingsTests: XCTestCase {

    func testDefaults() {
        let settings = SessionState.BioSettings()
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.coherenceThreshold, 0.6, accuracy: 0.001)
        XCTAssertEqual(settings.smoothingFactor, 0.3, accuracy: 0.01)
    }

    func testCodable() throws {
        let original = SessionState.BioSettings()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionState.BioSettings.self, from: encoded)
        XCTAssertEqual(original.enabled, decoded.enabled)
        XCTAssertEqual(original.coherenceThreshold, decoded.coherenceThreshold, accuracy: 0.001)
        XCTAssertEqual(original.smoothingFactor, decoded.smoothingFactor, accuracy: 0.001)
    }
}

// MARK: - SessionState.AudioSettings Tests

final class SessionStateAudioSettingsTests: XCTestCase {

    func testDefaults() {
        let settings = SessionState.AudioSettings()
        XCTAssertEqual(settings.volume, 0.8, accuracy: 0.001)
        XCTAssertEqual(settings.bpm, 120, accuracy: 0.001)
        XCTAssertEqual(settings.carrierFrequency, 440, accuracy: 0.001)
        XCTAssertTrue(settings.toneEnabled)
        XCTAssertEqual(settings.toneFrequency, 10, accuracy: 0.001)
    }
}

// MARK: - EchoelLogger Tests

final class EchoelLoggerTests: XCTestCase {

    func testSharedInstance() {
        let logger = EchoelLogger.shared
        XCTAssertNotNil(logger)
    }

    func testProfessionalLoggerAlias() {
        // ProfessionalLogger is a typealias for EchoelLogger
        let a: ProfessionalLogger = EchoelLogger.shared
        XCTAssertNotNil(a)
    }

    func testGlobalLogAlias() {
        // Global `log` is EchoelLogger.shared
        XCTAssertNotNil(log)
    }

    func testMinimumLevelFiltering() {
        let logger = EchoelLogger.shared
        let originalLevel = logger.minimumLevel
        logger.setMinimumLevel(.warning)
        logger.trace("This should be filtered")
        // Verify the minimum level was applied
        XCTAssertEqual(logger.minimumLevel, .warning)
        logger.setMinimumLevel(originalLevel)
        XCTAssertEqual(logger.minimumLevel, originalLevel)
    }

    func testLogDoesNotCrash() {
        let logger = EchoelLogger.shared
        // Verify logger is properly configured before exercising all methods
        XCTAssertNotNil(logger.minimumLevel)
        logger.log(.info, category: .audio, "Test message")
        logger.log(.error, category: .system, "Error test", metadata: ["key": "val"])
        logger.audio("Audio test")
        logger.midi("MIDI test")
        logger.performance("Perf test")
        // Verify logger still functional after burst of calls
        XCTAssertNotNil(logger.enabledCategories)
        XCTAssertFalse(logger.enabledCategories.isEmpty)
    }
}
#endif
