//  LockedBox.swift
//  Echoelmusic — Core
//
//  A one-value holder whose read and write are serialized by a lock.
//
//  WHY THIS EXISTS, precisely. A callback that a background producer CALLS and its
//  owner NILS is not safe as a bare `nonisolated(unsafe) var` — even though the
//  attribute makes the compiler accept it. `sink?(value)` is two steps: load the
//  optional, then call it. If the owner assigns `nil` between them, the closure's
//  captured context can be released while the call is in flight. That is a
//  use-after-free (EXC_BAD_ACCESS), not a torn read, and it does not care that a
//  closure reference happens to be pointer-width.
//
//  THE FIX IS THE LOAD, NOT THE LOCK-HELD CALL. `load()` copies the closure into a
//  local under the lock and returns it; the caller invokes it OUTSIDE the lock. The
//  local copy retains the context, so a concurrent `value = nil` can no longer pull
//  it out from underneath. Holding the lock across the call would be actively worse:
//  a 30 fps producer and a main-actor teardown would contend on every frame, and any
//  re-entrant assignment from inside the callback would deadlock.
//
//  This is deliberately NOT an actor. The producer is a `nonisolated` capture-queue
//  delegate that must not hop actors per frame — that flood of main-actor task
//  submissions is its own shipped bug (the biofeedback menu freeze, 10.76.48).

import Foundation

/// Thread-safe single-value holder. `@unchecked Sendable` because the lock, not the
/// type system, is what provides the safety — same contract as `RGBSampleQueue`.
final class LockedBox<Value>: @unchecked Sendable {

    private let lock = NSLock()
    private var stored: Value?

    init(_ initial: Value? = nil) { stored = initial }

    /// Read/write from any thread.
    var value: Value? {
        get { load() }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }

    /// Take a retained copy for immediate use. Call the result OUTSIDE any lock —
    /// see the file header for why the copy, not a lock-held call, is the fix.
    func load() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
