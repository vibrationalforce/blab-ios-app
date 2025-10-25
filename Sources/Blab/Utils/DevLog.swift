import Foundation

struct DevLog: Codable {
    enum LogLevel: String, Codable {
        case info
        case warning
        case error
    }

    let subsystem: String
    let message: String
    let timestamp: Date
    let severity: LogLevel
}

struct AuditManifest: Codable {
    let build: String
    let subsystem: String
    let tests: [String]
    let lint: String
    let warnings: Int
    let claudeReview: String

    init(build: String, subsystem: String, tests: [String], lint: String, warnings: Int, claudeReview: String = "pending") {
        self.build = build
        self.subsystem = subsystem
        self.tests = tests
        self.lint = lint
        self.warnings = warnings
        self.claudeReview = claudeReview
    }
}
