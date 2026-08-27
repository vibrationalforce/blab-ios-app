// MonitorTapWindow.swift
// Echoelmusic — Audio (feedback-guard spectrum source, #595)
//
// The 10.76.48 pattern, audio-input edition: the monitor tap's callback runs on the
// tap's I/O thread and must NOT hop to the main actor per buffer. It pushes samples
// into this lock-protected window with zero actor hops; the EXISTING ~15 Hz feedback-
// guard tick (main actor) copies the latest full window out and runs the FFT there.
// A torn window is impossible (the lock covers both sides); a STALE window merely
// delays the notch by one tick — but a FROZEN window (no new writes at all) is a
// different case, answered by `writeStamp` (#850, see its doc). `@unchecked Sendable`
// for the same reason as `RGBSampleQueue`: all shared state sits behind the one lock.
//
// NSLock in a TAP callback is deliberate and matches the repo's law: the tap thread is
// NOT the render thread (`MicrophoneManager` allocates in its tap for the same reason,
// and says so) — the audio-thread lock ban governs render blocks, not I/O taps.

import Foundation

final class MonitorTapWindow: @unchecked Sendable {

    private let lock = NSLock()
    private var ring: [Float]
    private var writeIndex = 0
    private var filled = 0
    /// #850 (the #848 review's F4): monotone count of `push` calls. `copyLatest`
    /// alone cannot say whether the audio it returns is NEW — once filled it returns
    /// the same window forever, and an engine halt that bypasses `stop(reason:)`
    /// (a session interruption) leaves the guard tick observing a FROZEN spectrum:
    /// a track whose growth already crossed the threshold then re-emits a candidate
    /// every tick and parks a notch band at full depth until the next start. The
    /// stamp lets the reader ask "did anything arrive since I last looked".
    private var stamp: UInt64 = 0
    let size: Int

    init(size: Int) {
        self.size = max(64, size)
        self.ring = [Float](repeating: 0, count: max(64, size))
    }

    /// TAP THREAD. Append samples, overwriting the oldest — never blocks for long
    /// (the reader holds the lock only for one copy at ~15 Hz).
    func push(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        lock.lock()
        for i in 0..<count {
            ring[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % size
        }
        filled = min(size, filled + count)
        stamp &+= 1
        lock.unlock()
    }

    /// MAIN ACTOR (guard tick). The stamp after the most recent `push` — equal to the
    /// value a previous call returned exactly when NO new audio arrived in between.
    /// Deliberately NOT reset by `clear()`: the stamp is an identity of writes, not of
    /// content, and resetting it could alias a value a reader still remembers.
    func writeStamp() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return stamp
    }

    /// MAIN ACTOR (guard tick). The latest `size` samples in time order, or nil until
    /// the window has filled once. Copies into the caller's reusable buffer so the
    /// tick allocates nothing per call.
    func copyLatest(into out: inout [Float]) -> Bool {
        guard out.count == size else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard filled == size else { return false }
        for i in 0..<size {
            out[i] = ring[(writeIndex + i) % size]
        }
        return true
    }

    /// Reset between monitoring sessions so a stale window cannot trigger a notch.
    func clear() {
        lock.lock()
        writeIndex = 0
        filled = 0
        lock.unlock()
    }
}
