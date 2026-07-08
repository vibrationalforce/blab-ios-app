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

/// Pre-encoded markers so the signal handler does NOT allocate (malloc may be
/// locked mid-crash). Built once at load. One per fatal signal so the surfaced
/// log distinguishes a bad-memory-access/heap fault (SIGSEGV/SIGBUS) from a
/// Swift runtime trap (SIGTRAP/SIGILL — precondition/force-unwrap/overflow) or
/// an abort (SIGABRT) — the single most useful datum for diagnosing the cause.
private let echoelCrashMarker: [UInt8] = Array("CRASH (signal caught) — see breadcrumbs above\n".utf8)
private let echoelCrashSEGV: [UInt8] = Array("CRASH SIGSEGV (bad memory access / heap) — see breadcrumbs above\n".utf8)
private let echoelCrashBUS: [UInt8]  = Array("CRASH SIGBUS (bad memory access) — see breadcrumbs above\n".utf8)
private let echoelCrashTRAP: [UInt8] = Array("CRASH SIGTRAP (Swift trap: precondition/force-unwrap/overflow) — see breadcrumbs above\n".utf8)
private let echoelCrashILL: [UInt8]  = Array("CRASH SIGILL (illegal instruction / Swift trap) — see breadcrumbs above\n".utf8)
private let echoelCrashABRT: [UInt8] = Array("CRASH SIGABRT (abort) — see breadcrumbs above\n".utf8)
private let echoelCrashFPE: [UInt8]  = Array("CRASH SIGFPE (arithmetic) — see breadcrumbs above\n".utf8)

/// Pre-allocated backtrace frame buffer so the signal handler can capture a
/// stack trace WITHOUT allocating (malloc may be locked mid-crash). 64 frames
/// is plenty for our call depth. `backtrace_symbols_fd` writes symbol names
/// straight to the fd (no malloc), so the crash log names the faulting function
/// even for a SIGTRAP — no dSYM or Xcode needed to read it.
private nonisolated(unsafe) var echoelBacktraceBuffer =
    [UnsafeMutableRawPointer?](repeating: nil, count: 64)

/// Pre-allocated buffer + markers for capturing the crashing thread/queue name.
/// libdispatch names its worker threads after the queue label, so this pins
/// WHICH queue a MainActor-isolation trap (dispatch_assert_queue) fired on.
/// All async-signal-safe: pthread_getname_np fills a fixed buffer, write() emits
/// the pre-encoded prefix/newline. No allocation.
private nonisolated(unsafe) let echoelThreadNameBuf =
    UnsafeMutablePointer<CChar>.allocate(capacity: 80)
private let echoelThreadPrefix: [UInt8] = Array("crash thread/queue: ".utf8)
private let echoelNewlineByte: [UInt8] = [0x0a]

/// Allocation-free: pick the pre-encoded marker for a received signal.
private func echoelCrashMarker(for sig: Int32) -> [UInt8] {
    switch sig {
    case SIGSEGV: return echoelCrashSEGV
    case SIGBUS:  return echoelCrashBUS
    case SIGTRAP: return echoelCrashTRAP
    case SIGILL:  return echoelCrashILL
    case SIGABRT: return echoelCrashABRT
    case SIGFPE:  return echoelCrashFPE
    default:      return echoelCrashMarker
    }
}

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
        // Name the build in the first line: every pasted diag log identifies its
        // version (triage step 1 — "is the fix you're verifying IN this build?"),
        // instead of guessing from timestamps against TestFlight upload times.
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        breadcrumb("launch v\(v) (\(b))")
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
                echoelCrashMarker(for: received).withUnsafeBufferPointer {
                    if let base = $0.baseAddress { _ = write(EchoelCrashLog.fd, base, $0.count) }
                }
                // Crashing thread/queue name (pins which queue a MainActor-isolation
                // trap fired on). Async-signal-safe: fixed buffer + raw writes.
                if pthread_getname_np(pthread_self(), echoelThreadNameBuf, 80) == 0,
                   strlen(echoelThreadNameBuf) > 0 {
                    echoelThreadPrefix.withUnsafeBufferPointer {
                        if let b = $0.baseAddress { _ = write(EchoelCrashLog.fd, b, $0.count) }
                    }
                    _ = write(EchoelCrashLog.fd, echoelThreadNameBuf, strlen(echoelThreadNameBuf))
                    echoelNewlineByte.withUnsafeBufferPointer {
                        if let b = $0.baseAddress { _ = write(EchoelCrashLog.fd, b, 1) }
                    }
                }
                // Async-signal-safe stack trace: backtrace() fills a pre-allocated
                // buffer, backtrace_symbols_fd() writes the symbol names directly to
                // the fd with no malloc. Pins the faulting function for a SIGTRAP.
                let frames = backtrace(&echoelBacktraceBuffer, Int32(echoelBacktraceBuffer.count))
                backtrace_symbols_fd(&echoelBacktraceBuffer, frames, EchoelCrashLog.fd)
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }
}
