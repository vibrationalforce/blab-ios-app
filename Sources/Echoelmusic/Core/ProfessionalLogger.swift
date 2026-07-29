// ProfessionalLogger.swift
// Echoelmusic - Structured Logging System
//
// Professional structured logging system
// Replaces all print() statements with proper logging
//
// Created by Echoelmusic Team
// Copyright 2026 Echoelmusic. MIT License.

import Foundation
#if canImport(os)
import os.log
#endif

/// Typealias for backwards compatibility
public typealias ProfessionalLogger = EchoelLogger

// MARK: - Log Level

/// Log severity levels
public enum LogLevel: Int, Comparable, CaseIterable, Sendable {
    case trace = 0
    case debug = 1
    case info = 2
    case notice = 3
    case warning = 4
    case error = 5
    case critical = 6

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var emoji: String {
        switch self {
        case .trace: return "🔍"
        case .debug: return "🐛"
        case .info: return "ℹ️"
        case .notice: return "📢"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }

    #if canImport(os)
    public var osLogType: OSLogType {
        switch self {
        case .trace, .debug: return .debug
        case .info, .notice: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
    #endif
}

// MARK: - Log Category

/// Log categories for filtering
public enum LogCategory: String, CaseIterable, Sendable {
    case audio = "Audio"
    case video = "Video"
    case streaming = "Streaming"
    case biofeedback = "Biofeedback"
    case lambda = "Lambda"
    case orchestral = "Orchestral"
    case midi = "MIDI"
    case network = "Network"
    case ui = "UI"
    case performance = "Performance"
    case accessibility = "Accessibility"
    case plugin = "Plugin"
    case system = "System"
    case collaboration = "Collaboration"
    case scoring = "Scoring"
    case hardware = "Hardware"
    case privacy = "Privacy"
    case recording = "Recording"
    case business = "Business"
    case automation = "Automation"
    case intelligence = "Intelligence"
    case spatial = "Spatial"
    case led = "LED"
    case social = "Social"
    case science = "Science"
    case analytics = "Analytics"
    case ai = "AI"
    case biosync = "Biosync"
    case security = "Security"
    case interface = "Interface"

    #if canImport(os)
    public var osLog: OSLog {
        OSLog(subsystem: "com.echoelmusic", category: rawValue)
    }
    #endif
}

// MARK: - Log Entry

/// A single log entry
public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String
    public let file: String
    public let function: String
    public let line: Int
    public let metadata: [String: String]

    public init(
        level: LogLevel,
        category: LogCategory,
        message: String,
        file: String,
        function: String,
        line: Int,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = Date()
        self.level = level
        self.category = category
        self.message = message
        self.file = file
        self.function = function
        self.line = line
        self.metadata = metadata
    }

    /// Thread-safe time formatting using C strftime + milliseconds.
    /// DateFormatter is NOT thread-safe — concurrent access from multiple
    /// logging threads corrupts internal state or crashes.
    private static func formatTime(_ date: Date) -> String {
        var time = time_t(date.timeIntervalSince1970)
        var tm = tm()
        localtime_r(&time, &tm)
        let ms = Int((date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
        var buf = [CChar](repeating: 0, count: 16)
        strftime(&buf, buf.count, "%H:%M:%S", &tm)
        return String(cString: buf) + String(format: ".%03d", ms)
    }

    public var formattedMessage: String {
        let timeString = Self.formatTime(timestamp)

        let fileName = URL(fileURLWithPath: file).lastPathComponent
        return "\(level.emoji) [\(timeString)] [\(category.rawValue)] \(message) (\(fileName):\(line))"
    }
}

// MARK: - Log Output

/// Log output destination
public protocol LogOutput: Sendable {
    func write(_ entry: LogEntry)
}

/// Console output
public final class ConsoleOutput: LogOutput, @unchecked Sendable {
    public static let shared = ConsoleOutput()

    public func write(_ entry: LogEntry) {
        #if canImport(os)
        os_log(
            "%{public}@",
            log: entry.category.osLog,
            type: entry.level.osLogType,
            entry.message
        )
        #endif
    }
}

/// File output
public final class FileOutput: LogOutput, @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.echoelmusic.log.file")

    public init(fileName: String = "echoelmusic.log") {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileURL = documentsPath.appendingPathComponent(fileName)
    }

    public func write(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let line = "\(entry.formattedMessage)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.fileURL)
                }
            }
        }
    }
}

// MARK: - Professional Logger

/// Main professional logging system (renamed from Logger to avoid os.log.Logger conflict)
public final class EchoelLogger: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = EchoelLogger()

    // MARK: - Properties

    /// Config properties protected by configLock (read from any thread, written rarely)
    private let configLock = AudioUnfairLock()
    private var _minimumLevel: LogLevel = .debug
    private var _enabledCategories: Set<LogCategory> = Set(LogCategory.allCases)

    public var minimumLevel: LogLevel {
        get { configLock.lock(); defer { configLock.unlock() }; return _minimumLevel }
        set { configLock.lock(); defer { configLock.unlock() }; _minimumLevel = newValue }
    }
    public var enabledCategories: Set<LogCategory> {
        get { configLock.lock(); defer { configLock.unlock() }; return _enabledCategories }
        set { configLock.lock(); defer { configLock.unlock() }; _enabledCategories = newValue }
    }

    private var outputs: [any LogOutput] = [ConsoleOutput.shared]
    private let queue = DispatchQueue(label: "com.echoelmusic.logger", qos: .utility)

    // MARK: - In-Memory Log Storage

    private var entries: [LogEntry] = []

    /// How many entries the in-memory ring keeps. 400, not the 10 000 it was.
    ///
    /// TWO REASONS, and the second is the expensive one.
    ///
    /// SIZE. This array has TWO readers — `getRecentEntries` and `exportLogs(since:)` —
    /// and NEITHER has a caller anywhere in the repo (verified 2026-07-29; review caught me
    /// naming only the first, and `exportLogs` is the one whose shape the cap actually
    /// binds: it takes a timestamp, not a page). The diagnostics sheet reads
    /// `EchoelCrashLog.currentLog()`, not this. So the buffer is write-only today: 10 000
    /// `LogEntry` values, each a `UUID` + `Date` + two enums + THREE `String`s (message,
    /// file, function) + a `Dictionary`, for the life of the process.
    ///
    /// Be honest about the size, because "10 000 on a 200 MB budget" invites a bigger
    /// number than is real: `file`/`function` come from `#file`/`#function`, which are
    /// literals with immortal static storage, so the per-entry heap cost is essentially
    /// just the interpolated `message`. The inline saving from 10 000 → 400 is on the order
    /// of a megabyte, not many. That is why the cost-per-call half below is the real story.
    /// 400 still covers `getRecentEntries`' default page of 100 four times over WHEN
    /// UNFILTERED; a `level:`/`category:` query draws that page from a 400-entry raw
    /// window, so re-check this number when a reader is finally wired up.
    ///
    /// COST PER LOG CALL. This is the part that is not about memory at all. The old trim
    /// was `removeFirst(count - max)` on a Swift `Array`, which is O(n) — it shifts every
    /// remaining element down. Once the buffer was full, EVERY subsequent log line paid a
    /// ~10 000-element memmove, forever, to make room for one entry. Trimming to a low-water
    /// mark instead amortises that over `cap - lowWater` appends; see `trimCount`.
    private let maxEntries: Int = 400

    /// How many entries to drop, given the current count and the cap. `0` = leave it alone.
    ///
    /// Pure and static so the amortisation is testable without touching the logger's serial
    /// queue or its global singleton — the trim runs inside a `queue.async`, which no unit
    /// test can observe deterministically.
    ///
    /// Trims down to a LOW-WATER mark (¾ of the cap) rather than exactly to the cap. That
    /// one change is the whole point: trimming to the cap means the very next append is over
    /// again, so the O(n) shift runs on every single log call once the buffer fills. Going
    /// to ¾ buys `cap / 4` cheap appends between shifts.
    /// `cap - cap / 4` rather than `(cap * 3) / 4`: same value for every cap ≥ 4 and no
    /// multiply to overflow. The overflow was unreachable — it needs `currentCount > cap`
    /// with `cap > Int.max/3`, i.e. an array of 10^18 elements — but the subtraction is
    /// free and removes the question.
    ///
    /// Trap-safety, checked exhaustively rather than assumed, because `removeFirst(n)`
    /// traps on a negative `n` and on `n > count`: for any `currentCount > cap ≥ 1`,
    /// `1 ≤ lowWater ≤ cap < currentCount`, so `1 ≤ drop ≤ currentCount - 1`.
    static func trimCount(currentCount: Int, cap: Int) -> Int {
        guard cap > 0, currentCount > cap else { return 0 }
        let lowWater = Swift.max(1, cap - cap / 4)
        return currentCount - lowWater
    }

    // MARK: - Configuration

    /// Add output destination (thread-safe)
    public func addOutput(_ output: any LogOutput) {
        queue.async { [weak self] in
            self?.outputs.append(output)
        }
    }

    /// Enable file logging
    public func enableFileLogging(fileName: String = "echoelmusic.log") {
        addOutput(FileOutput(fileName: fileName))
    }

    /// Set minimum log level
    public func setMinimumLevel(_ level: LogLevel) {
        minimumLevel = level
    }

    /// Enable specific categories only
    public func setEnabledCategories(_ categories: Set<LogCategory>) {
        enabledCategories = categories
    }

    // MARK: - Logging Methods

    /// Core logging method
    public func log(
        _ level: LogLevel,
        category: LogCategory,
        _ message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= minimumLevel else { return }
        guard enabledCategories.contains(category) else { return }

        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata
        )

        queue.async { [weak self] in
            guard let self = self else { return }

            // Store entry
            self.entries.append(entry)
            let drop = Self.trimCount(currentCount: self.entries.count, cap: self.maxEntries)
            if drop > 0 { self.entries.removeFirst(drop) }

            // Write to outputs
            for output in self.outputs {
                output.write(entry)
            }
        }
    }

    // MARK: - Convenience Methods

    public func trace(_ message: String, category: LogCategory = .system, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(.trace, category: category, message, file: file, function: function, line: line)
    }

    public func debug(_ message: String, category: LogCategory = .system, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(.debug, category: category, message, file: file, function: function, line: line)
    }

    public func info(_ message: String, category: LogCategory = .system, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(.info, category: category, message, file: file, function: function, line: line)
    }

    public func notice(_ message: String, category: LogCategory = .system, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(.notice, category: category, message, file: file, function: function, line: line)
    }

    public func warning(_ message: String, category: LogCategory = .system, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(.warning, category: category, message, file: file, function: function, line: line)
    }

    public func error(_ message: String, category: LogCategory = .system, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(.error, category: category, message, file: file, function: function, line: line)
    }

    public func critical(_ message: String, category: LogCategory = .system, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(.critical, category: category, message, file: file, function: function, line: line)
    }

    // MARK: - Category-Specific Loggers

    public func audio(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .audio, message, file: file, function: function, line: line)
    }

    public func video(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .video, message, file: file, function: function, line: line)
    }

    public func streaming(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .streaming, message, file: file, function: function, line: line)
    }

    public func biofeedback(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .biofeedback, message, file: file, function: function, line: line)
    }

    public func lambda(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .lambda, message, file: file, function: function, line: line)
    }

    public func orchestral(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .orchestral, message, file: file, function: function, line: line)
    }

    public func midi(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .midi, message, file: file, function: function, line: line)
    }

    public func network(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .network, message, file: file, function: function, line: line)
    }

    public func performance(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .performance, message, file: file, function: function, line: line)
    }

    public func scoring(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .scoring, message, file: file, function: function, line: line)
    }

    public func hardware(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .hardware, message, file: file, function: function, line: line)
    }

    public func privacy(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .privacy, message, file: file, function: function, line: line)
    }

    public func recording(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .recording, message, file: file, function: function, line: line)
    }

    public func business(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .business, message, file: file, function: function, line: line)
    }

    public func automation(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .automation, message, file: file, function: function, line: line)
    }

    public func intelligence(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .intelligence, message, file: file, function: function, line: line)
    }

    public func spatial(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .spatial, message, file: file, function: function, line: line)
    }

    public func led(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .led, message, file: file, function: function, line: line)
    }

    public func social(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .social, message, file: file, function: function, line: line)
    }

    public func science(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .science, message, file: file, function: function, line: line)
    }

    public func accessibility(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .accessibility, message, file: file, function: function, line: line)
    }

    public func analytics(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .analytics, message, file: file, function: function, line: line)
    }

    public func ai(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        self.log(level, category: .ai, message, file: file, function: function, line: line)
    }

    // MARK: - Log Retrieval

    /// Get recent log entries (thread-safe).
    ///
    /// ⚠️ NO CALLER in `Sources/` (verified 2026-07-29). The in-app diagnostics sheet reads
    /// `EchoelCrashLog.currentLog()`, not this — so the in-memory ring this reads is
    /// write-only today. Stated here rather than left to be rediscovered: it is why the
    /// ring was cut from 10 000 entries to 400. Wiring a real reader is fine; sizing the
    /// buffer for a reader that does not exist was not.
    public func getRecentEntries(count: Int = 100, level: LogLevel? = nil, category: LogCategory? = nil) -> [LogEntry] {
        queue.sync {
            var filtered = entries

            if let level = level {
                filtered = filtered.filter { $0.level >= level }
            }

            if let category = category {
                filtered = filtered.filter { $0.category == category }
            }

            return Array(filtered.suffix(count))
        }
    }

    /// Export logs as string (thread-safe)
    public func exportLogs(since: Date? = nil) -> String {
        queue.sync {
            var filtered = entries

            if let since = since {
                filtered = filtered.filter { $0.timestamp >= since }
            }

            return filtered.map { $0.formattedMessage }.joined(separator: "\n")
        }
    }

    /// Clear all logs
    public func clear() {
        queue.async { [weak self] in
            self?.entries.removeAll()
        }
    }
}

// MARK: - Global Logger Access

/// Global logger instance
public let echoelLog = EchoelLogger.shared

/// Alias for backward compatibility (many files use 'log')
public let log = EchoelLogger.shared
