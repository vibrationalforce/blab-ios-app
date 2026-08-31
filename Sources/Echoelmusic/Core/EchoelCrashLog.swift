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

    /// The retained crash AS IT STOOD AT LAUNCH, before this launch's own retention could
    /// overwrite it. Captured once by `begin()` so `SafeModeView` — the screen whose whole
    /// job is to render when nothing else can — reads memory and never a file (#917).
    nonisolated(unsafe) static var retainedCrashAtLaunch: String = ""

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
        // #916: KEEP the run that just ended, if it ended badly. `previousSession` is the
        // only copy of a crashed run and it lives for exactly ONE launch — the `O_TRUNC`
        // above has already thrown the file away, and the next launch throws this copy away
        // too. Seven device logs into the `isInputConnToConverter` family, a user who
        // dismisses the auto-surfaced sheet (or a background kill, which
        // `looksLikeUnseenCrash` deliberately does not surface) loses the evidence for good.
        //
        // ⚠️ THE PLACE IS PART OF THE DECISION, exactly like a ladder rung (#862b): this runs
        // AFTER `installHandlers()`, so a fault inside the write is itself caught, and AFTER
        // the version line, so the log already names the build even if this is where it dies.
        // #917: the retained file as it stands right now, read ONCE and reused by the block
        // below as its `existing`.
        //
        // ⛔ THE REASON FIRST GIVEN FOR TAKING IT HERE WAS FALSE, and a review disproved it by
        // case analysis rather than by argument. It claimed a post-write snapshot "would,
        // after an ordinary crash, offer the very run it is already showing". It would not:
        // a retained log is a textual slice of some run, so a marker in the slice implies the
        // marker was in that run, and `recoveryExport`'s gate then declines on its FIRST
        // clause. In every reachable state the composed text is byte-identical either way.
        // The non-duplication property comes entirely from that gate — nothing here.
        // What this position DOES buy is one file read instead of two, and a name that means
        // what it says.
        retainedCrashAtLaunch = lastCrashLog()
        if let keep = crashToRetain(from: previousSession) {
            // ⛔ THE FIRST DRAFT OF #916 BROKE THE LAW THE COMMENT ABOVE CITES, twice in two
            // lines. It wrote ONE line, AFTER the write, stating an outcome it had not
            // observed. (a) A witness behind the step sees nothing: if the launch dies inside
            // this write — jetsam while up to the whole budget is serialised and renamed —
            // the log carries no trace that retention was even attempted, i.e. a silent death
            // inside the code whose entire subject is preserving deaths. (b) `try?` discards
            // the result, so "retained … N chars" would have been printed for a full disk or
            // a file-protection refusal too, and triage would have gone looking for a sibling
            // file that does not exist. A rung before the step, and an outcome only when it
            // was actually seen.
            //
            // Reuses the snapshot above rather than reading the file a second time.
            // ⛔ THE FIRST DRAFT CALLED `lastCrashLog()` AGAIN HERE and, thirteen lines below
            // an unconditional read, described the cost as "only on a launch that follows a
            // bad run". Both halves were false the moment #917 landed: the read happens on
            // EVERY launch, and on a bad-run launch it happened twice.
            if shouldReplaceRetained(candidate: keep, existing: retainedCrashAtLaunch) {
                breadcrumb("retaining the previous run's crash log (\(keep.count) chars)")
                // `atomically: true` is what makes "a failure leaves the previously retained
                // file in place" true — it writes a temporary and renames. Without that flag a
                // failed write could truncate the only copy: the opposite of this slice.
                let wrote: Void? = try? keep.write(to: lastCrashURL,
                                                   atomically: true,
                                                   encoding: .utf8)
                breadcrumb(wrote == nil
                           ? "retain failed - the previous run's log could not be kept"
                           : "retain ok")
            } else {
                breadcrumb("retain declined - the kept log carries a signal marker, this one does not")
            }
        }
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

    // MARK: - Keeping the last crash across launches (#916)

    /// ⭐ WHY ANY OF THIS EXISTS. `begin()` opens the log with `O_TRUNC`, so the file on disk
    /// holds exactly ONE run. A crashed run survives only in `previousSession`, in memory,
    /// for the length of the launch that follows it. Share it then or it is gone.
    ///
    /// ⚠️ NEWEST crash wins, not first — a retained file is overwritten by the next crash that
    /// is captured. Keeping the oldest would preserve the least useful one: the founder
    /// iterates on builds, and the crash worth reading is the one from the build in hand.
    /// ⚠️ "Newest wins" is the rule AMONG CRASHES ONLY. `shouldReplaceRetained` is the whole
    /// policy, and it also refuses to let an unmarked run evict a marked one — do not read
    /// this line as the complete rule.
    ///
    /// ⭐ One spelling, in Core, for the same reason as the marker constants above: the WRITER
    /// (`diagnosticsExport`) and any READER of a pasted log are far apart, and a header only
    /// one of them spells right fails silently (#416).
    static let retainedCrashHeader = "=== RETAINED CRASH (an earlier run that ended badly) ==="

    /// ⚠️ CHARACTERS, NOT BYTES — and the name says so on purpose. `String.suffix(_:)` counts
    /// `Character`s, while `wc -c` counts bytes; this repo treats those as different
    /// measurements (`.claude/rules/context.md` §2). A log carrying German or a marker glyph
    /// costs more bytes than characters, so the retained FILE can be larger than this number.
    static let retainedCrashCharacterBudget = 64_000

    /// ⭐ WHY A TRIMMED LOG STILL CARRIES ITS FIRST LINE. The tail is where the crash is, so
    /// the tail is what a budget must keep — but the FIRST line of a run is the build banner,
    /// and triage step 1 is "is the fix you are verifying IN this build?". A retained crash is
    /// read days or weeks later, on a different build; a pure tail slice would hand over a
    /// crash that cannot be dated to a version. So an oversized log keeps its launch line, this
    /// marker to say the middle is gone, and then the tail.
    ///
    /// ⛔ The first draft of #916 was a plain `suffix(budget)`. It was self-contradicting: this
    /// file's own guard argues the export must name the build in its first line, and for
    /// exactly the logs big enough to be trimmed that head line was the first thing cut.
    static let retainedCrashTrimMarker =
        "...  [earlier lines trimmed - launch line above, end of the run below]"

    /// What, if anything, `begin()` should keep from the run that just ended.
    ///
    /// Pure on purpose: the blocking bundle can drive this, while the file write wrapped
    /// around it at the call site is the part no test can reach.
    ///
    /// ⚠️ WHAT AN OVERSIZED LOG KEEPS: its FIRST LINE, a trim marker, then the TAIL. The crash
    /// marker, the signal handler's backtrace and the last rungs of whichever ladder was
    /// climbing all sit at the END, so the tail is the part worth saving; the first line is
    /// kept on top of it because it is the build banner (see `retainedCrashTrimMarker`). Under
    /// the budget nothing is cut at all.
    ///
    /// The decision of WHAT counts as "ended badly" is not re-made here — it is
    /// `looksLikeUnseenCrash`, whose semantics `ACleanExitIsNotACrashTests` already pins.
    static func crashToRetain(from previous: String) -> String? {
        guard looksLikeUnseenCrash(previous) else { return nil }
        guard previous.count > retainedCrashCharacterBudget else { return previous }
        let head = String(previous.prefix(while: { $0 != "\n" })) + "\n"
            + retainedCrashTrimMarker + "\n"
        let room = retainedCrashCharacterBudget - head.count
        // A launch line longer than the whole budget is not a real log; fall back to the
        // plain tail rather than return a "head" that is nothing but the banner.
        guard room > 0 else { return String(previous.suffix(retainedCrashCharacterBudget)) }
        return head + String(previous.suffix(room))
    }

    /// May the newly captured `candidate` overwrite what is already retained?
    ///
    /// ⛔ THE FIRST DRAFT OF #916 HAD NO SUCH QUESTION, and its retained slot could be
    /// destroyed by an ordinary session. `looksLikeUnseenCrash` has TWO arms, and only the
    /// first requires a marker: arm 2 is "reached Start and did not end in `background`",
    /// which is also true of a device reboot, a battery death, or a run stopped from Xcode.
    /// So: launch A takes a SIGSEGV and is retained WITH its backtrace and named signal;
    /// launch B taps Start and ends without a background transition; launch C overwrites the
    /// gold copy with a log that has no marker, no backtrace and nothing to triage. The slot
    /// holds one file, and "newest wins" alone is the wrong rule across two different
    /// strengths of evidence.
    ///
    /// The rule: a marked candidate always wins (newest crash, as documented). An UNMARKED
    /// candidate wins only when what is already kept is unmarked too.
    static func shouldReplaceRetained(candidate: String, existing: String) -> Bool {
        if candidate.contains(crashMarker) { return true }
        return !existing.contains(crashMarker)
    }

    /// The text the reachable "Diagnostics" row shows: this run, then the retained crash.
    ///
    /// ⚠️ WITH NO RETAINED CRASH THE RESULT IS BYTE-IDENTICAL TO `current`, header included —
    /// i.e. absent. The ordinary case must not grow a heading for a section that is not there.
    ///
    /// ⚠️ `current` comes FIRST and the result always starts with it exactly. That order is not
    /// cosmetic: the first line of a run names the build, and triage step 1 is "is the fix you
    /// are verifying IN this build?". A pasted export must answer that in its first line.
    static func diagnosticsExport(current: String, retainedCrash: String) -> String {
        guard !retainedCrash.isEmpty else { return current }
        return current + "\n\n" + retainedCrashHeader + "\n" + retainedCrash
    }

    /// What the SAFE MODE recovery screen shows (#917).
    ///
    /// ⭐ THE HOLE THIS CLOSES: on a safe-mode launch the run immediately before it can be the
    /// RECOVERY launch — short, markerless, useless — while the real abort sits in the
    /// retained file. The screen whose entire purpose is "share this with the developer" then
    /// shows the wrong run.
    ///
    /// ⚠️ NARROWER THAN THE FIRST DRAFT CLAIMED, and the difference decides how often this
    /// fires. A SIGSEGV/SIGABRT writes a marker, so on the launch straight after one the gate
    /// declines and the screen was already showing the right run — #917 changes nothing there.
    /// It applies when the RECOVERY launch itself ends without a marker: the user force-quits
    /// from this screen instead of tapping Continue (so `LaunchGuard.reset()` never runs and
    /// the streak keeps the next launch in safe mode), or a watchdog/jetsam kill beats the
    /// signal handler. The first draft said flatly "the run before it IS the recovery launch",
    /// which would have had the next reader plan from a case that is the exception.
    ///
    /// ⚠️ THE GATE IS "previous has no marker AND the retained one does", and it is chosen so
    /// the block can never DUPLICATE. A retained log is a slice of some earlier run, so a
    /// marker in the slice means that run carried one; if `previous` has no marker it cannot
    /// be the run that was retained. The obvious simpler gate — `!looksLikeUnseenCrash
    /// (previous)` — would have hidden the retained abort in exactly the case worth showing
    /// it: a markerless arm-2 run (reboot, battery, Xcode stop) sitting in front of a real
    /// SIGABRT.
    static func recoveryExport(previous: String, retainedCrash: String) -> String {
        guard !previous.contains(crashMarker), retainedCrash.contains(crashMarker) else {
            return previous
        }
        // An unreadable previous session (file protection, or the computed `fileURL` landing
        // in a different container between two launches) would otherwise compose a text that
        // OPENS with two blank lines and no build banner — while `diagnosticsExport`'s own doc
        // insists the first line must name the build. Lead with the heading instead; the
        // retained run carries its own launch line directly under it.
        guard !previous.isEmpty else { return retainedCrashHeader + "\n" + retainedCrash }
        return diagnosticsExport(current: previous, retainedCrash: retainedCrash)
    }

    /// The recovery screen's text, from values captured at launch — no file I/O, so the one
    /// screen that must always render never depends on the disk.
    static func recoveryExport() -> String {
        recoveryExport(previous: previousSession, retainedCrash: retainedCrashAtLaunch)
    }

    /// Sibling of the live log, in the same directory — one definition of WHERE (`fileURL`).
    ///
    /// ⚠️ THAT GUARANTEES "the same directory at the same instant", NOT "never different".
    /// `fileURL` is COMPUTED: it re-asks `FileManager` for the Documents container on every
    /// access and falls back to `temporaryDirectory` when that fails. A transient failure
    /// between two accesses can therefore put the live log in one place and this one in the
    /// other. Hoisting the directory into a single resolved `static let` would close it; that
    /// is a separate change to a launch-critical path, so the limit is stated instead of
    /// being claimed away.
    private static var lastCrashURL: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("echoel_diag_last_crash.log")
    }

    /// The retained crash log, or "" when none was ever kept.
    ///
    /// ⚠️ NOTHING CLEARS THIS FILE, and there is no in-app way to. Once a crash is retained
    /// every later Diagnostics export carries it, indefinitely. That is defensible — the
    /// retained text keeps its own launch line, so a stale crash is always dateable and
    /// attributable to the build it happened on, and `retainedCrashHeader` labels it as an
    /// earlier run — but it is a consequence, not an accident, so it is written down rather
    /// than discovered later by someone wondering why an old crash keeps appearing.
    ///
    /// ⚠️ AND IT ENLARGES THE SHARE SHEET — and, since #917, the SAFE MODE screen too, whose
    /// single `Text` has no `lineLimit` and whose `ShareLink` carries the same string. Two files (`AudioConfiguration.sanitisedRoute`,
    /// `AudioInputManager`) bound a route name to 80 characters precisely because
    /// `currentLog()` reads a whole log into one String for that sheet. #916 appends up to
    /// the budget again on top of it. Those bounds are not weakened — the reason for them is
    /// unchanged — but the combined export is now bigger than the file either of them was
    /// reasoning about, and pretending otherwise beside their own argument would be the shape
    /// this repo calls a claim standing next to its own refutation.
    static func lastCrashLog() -> String {
        (try? String(contentsOf: lastCrashURL, encoding: .utf8)) ?? ""
    }

    /// This run plus the retained crash — what the reachable Diagnostics row renders.
    static func diagnosticsExport() -> String {
        diagnosticsExport(current: currentLog(), retainedCrash: lastCrashLog())
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
