//  LockedBox.swift
//  Echoelmusic — Core
//
//  A one-value holder whose read and write are serialized by a lock.
//
//  WHY THIS EXISTS, precisely. A callback that a background producer CALLS and its
//  owner NILS is not safe as a bare `nonisolated(unsafe) var` — even though the
//  attribute makes the compiler accept it. The attribute is a PROMISE that no such
//  race exists, not a mitigation for one.
//
//  THE WINDOW IS LOAD→RETAIN, NOT LOAD→CALL. (Corrected after review; the first draft
//  of this comment said load→call, and the difference decides whether the fix below
//  even works.) `sink?(value)` lowers to `load [copy]`: load the reference, retain it,
//  then call. A concurrent `nil` landing between the load and the retain retains — or
//  over-releases — freed memory. When the optimiser elides that retain, believing the
//  owning class keeps the value alive, the window widens to the whole call. Either way
//  it is undefined behaviour and can surface as EXC_BAD_ACCESS. It is a use-after-free,
//  not a torn read, so "a closure reference is pointer-width" is no defence.
//
//  THE FIX IS THE RETAIN-UNDER-LOCK, NOT A LOCK-HELD CALL. `load()` computes its return
//  value — which retains — before `defer { unlock() }` runs, so the retain happens
//  inside the critical section. The caller then invokes the copy OUTSIDE the lock.
//  Holding the lock across the call would be actively worse: a 15 fps producer and a
//  main-actor teardown contending on every frame, and a deadlock the moment a callback
//  touched the box re-entrantly.
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
            // The old value is released OUTSIDE the lock, deliberately. `stored = newValue`
            // drops the last reference to the previous closure, which runs its context's
            // destructor, which releases everything it captured, which can run arbitrary
            // `deinit`. Any of that touching this box again — a `deinit` that clears a
            // callback, say — would deadlock hard against a non-recursive `NSLock`, on the
            // MainActor. Found by review: the header above warns about exactly this
            // re-entrancy and the first draft then left the one path it owns wide open.
            lock.lock()
            let old = stored
            stored = newValue
            lock.unlock()
            withExtendedLifetime(old) {}   // `old` dies here, with no lock held
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
