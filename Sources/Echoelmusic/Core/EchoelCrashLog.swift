//
//  EchoelCrashLog.swift
//  Echoelmusic — Core
//
//  Lightweight on-device diagnostics. Writes a breadcrumb at each step of risky
//  flows (biofeedback start, generate) and best-effort captures crashes. The
//  PREVIOUS session's log is surfaced on the next launch so the user can share it
//  in one tap — no Settings → Analytics spelunking. Purely diagnostic; no PII.
//

import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Pre-encoded marker so the signal handler does NOT allocate (malloc may be
/// locked mid-crash). Built once at load.
private let echoelCrashMarker: [UInt8] = Array("CRASH (signal caught) — see breadcrumbs above\n".utf8)

enum EchoelCrashLog {

    /// The full log from the previous run (empty on first launch). Read by the UI
    /// to offer a one-tap share when the last run ended in a crash.
    nonisolated(unsafe) static var previousSession: String = ""

    nonisolated(unsafe) private static var fd: Int32 = -1

    private static var fileURL: URL {
        let dir = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("echoel_diag.log")
    }

    /// Call once, as early as possible at launch. Captures the prior log, opens a
    /// fresh one, installs crash handlers.
    static func begin() {
        let url = fileURL
        previousSession = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        fd = open(url.path, O_CREAT | O_TRUNC | O_WRONLY, 0o644)
        installHandlers()
        breadcrumb("launch")
    }

    /// Append a timestamped step marker. Best-effort, any thread, no throw.
    static func breadcrumb(_ message: String) {
        guard fd >= 0 else { return }
        let line = "\(String(format: "%.3f", Date().timeIntervalSince1970))  \(message)\n"
        var bytes = Array(line.utf8)
        _ = write(fd, &bytes, bytes.count)
    }

    /// The current run's log so far (for the manual "Diagnostics" button).
    static func currentLog() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    private static func installHandlers() {
        // ObjC / NSException path (no allocation constraints here).
        NSSetUncaughtExceptionHandler { exception in
            EchoelCrashLog.breadcrumb("CRASH exception: \(exception.name.rawValue): \(exception.reason ?? "")")
            for frame in exception.callStackSymbols { EchoelCrashLog.breadcrumb("  \(frame)") }
        }
        // Fatal signals (incl. Swift trap → SIGTRAP/SIGILL, bad access → SIGSEGV/
        // SIGBUS). Handler stays allocation-free: writes a pre-encoded marker only.
        let fatal: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        for sig in fatal {
            signal(sig) { received in
                echoelCrashMarker.withUnsafeBufferPointer {
                    if let base = $0.baseAddress { _ = write(EchoelCrashLog.fd, base, $0.count) }
                }
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }
}
