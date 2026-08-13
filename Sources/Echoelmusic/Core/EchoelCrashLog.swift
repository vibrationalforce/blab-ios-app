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

    // MARK: - Reading the previous session (#582)

    /// The breadcrumb vocabulary the auto-surface heuristic below reads back.
    ///
    /// ⭐ These are constants and not literals at each site because the WRITER and the
    /// READER are two files apart, and a marker that only one of them spells right fails
    /// SILENTLY — the reader simply never matches, and the feature turns off without a
    /// single red test. One definition per decision (#416).
    static let startTappedMarker = "Start tapped"
    static let crashMarker = "CRASH"
    static let backgroundPhase = "background"

    /// The one spelling of a scene-phase transition line. `EchoelmusicApp`'s
    /// `.onChange(of: scenePhase)` emits it; `lastScenePhase(in:)` is its exact inverse.
    /// The emitted text is byte-identical to what founder logs have always carried
    /// (`scene: inactive → background`) — this only stops the shape from being spelled twice.
    static func sceneTransition(from old: String, to new: String) -> String {
        "scene: \(old) \(sceneArrow) \(new)"
    }

    /// ⚠️ Deliberately a bare arrow, NOT `" → "` with its spaces baked in. The spaces live
    /// in `sceneTransition` above; the parser splits on this token and trims. Folding the
    /// padding into the constant would make a log line with a double space silently unparsable.
    static let sceneArrow = "→"

    /// The phase named by the LAST scene transition in a log, or nil if it has none.
    ///
    /// ⚠️ "Last", not "contains". A long session backgrounds and returns many times; a log
    /// that mentions `background` anywhere says nothing about how the session ENDED. The
    /// difference is the whole point of the heuristic below — `contains` would suppress the
    /// crash report for every user who ever switched apps mid-session.
    ///
    /// Only transition lines count. `EchoelmusicApp` also writes `scene: audio resumed`,
    /// `scene: audio continues` and `scene: idle audio engine stopped (2.5.4)` — same prefix,
    /// no arrow, not a phase — so the arrow is what selects, never the prefix.
    static func lastScenePhase(in log: String) -> String? {
        var last: String?
        for line in log.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("scene: "), let arrow = line.range(of: sceneArrow) else { continue }
            let phase = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            if !phase.isEmpty { last = phase }
        }
        return last
    }

    /// Did the previous session end somewhere the user could NOT see it end?
    ///
    /// ⛔ THE BUG THIS REPLACES (#582): the gate was `contains("Start tapped") || contains("CRASH")`,
    /// and `Start tapped` is written by the ordinary biofeedback Start button. So EVERY launch
    /// that followed a normal session in which the user pressed Start opened with a raw log
    /// dump on top of the app. Not on a crash — on the app's core interaction having been used.
    /// #580 made it worse by putting that sheet over a full-bleed visual with no chrome behind it.
    ///
    /// What the original heuristic actually wanted is still here and still worth having: a
    /// foreground death — jetsam, watchdog, a kill that beats the signal handler — writes NO
    /// crash marker, so "reached Start and never left the foreground" is the only evidence
    /// there is. The repair is not to drop that arm; it is to subtract the clean exits from it.
    ///
    /// - A real crash marker always surfaces, backgrounded or not.
    /// - Otherwise the session must have reached Start AND not have ended in `background`.
    ///
    /// ⚠️ HONEST LIMIT: an app that is backgrounded and then killed while in the background is
    /// reported as clean. That is deliberate — it is what iOS does to every backgrounded app,
    /// every day, and it is indistinguishable from a normal exit from the outside. The log is
    /// still there under Save & Export → Diagnostics; it just no longer opens itself.
    static func looksLikeUnseenCrash(_ log: String) -> Bool {
        if log.contains(crashMarker) { return true }
        guard log.contains(startTappedMarker) else { return false }
        return lastScenePhase(in: log) != backgroundPhase
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
