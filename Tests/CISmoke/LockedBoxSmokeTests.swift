// LockedBoxSmokeTests.swift
// Echoel — the holder that stands between "switch biofeedback off" and EXC_BAD_ACCESS.
//
// THE DEFECT (#213). `CameraCapture.onFrame` was a bare `nonisolated(unsafe) var`,
// CALLED on the capture queue ~30×/s and NILLED on the MainActor by
// `CameraRPPGBioPublisher.stop()`. `sink?(buffer)` is a load followed by a call; a `nil`
// landing between them can release the closure's captured context while that call is
// running. Not a torn read — a use-after-free, on the most ordinary gesture in the app.
//
// WHY IT LIVES IN CISmoke: this is the blocking bundle (see `SilenceClassSmokeTests` for
// the full argument — `project.yml`'s `EchoelmusicTests` target sources only this
// directory). A crash class earns a test that can actually fail a build.
//
// WHAT THESE TESTS CANNOT DO. They cannot reproduce the race — a passing threaded test
// proves nothing about a data race, and a flaky one in the BLOCKING gate is worse than
// no test at all. What they pin is the MECHANISM the fix rests on: that a value taken
// out of the box stays alive and callable after the box is cleared. If someone "simplifies"
// `LockedBox` back into a plain stored property, or rewrites a call site as
// `if box.value != nil { box.value!(x) }` — two loads, the race straight back — the
// deallocation test below fails. That is the guard that was actually available here.

import XCTest
@testable import Echoelmusic

final class LockedBoxSmokeTests: XCTestCase {

    // MARK: - The mechanism the fix rests on

    /// THE REGRESSION TEST. A closure taken out of the box must survive the box being
    /// cleared — that is the whole reason `load()` returns a copy instead of the call
    /// happening through the stored property.
    func testALoadedClosureStillRunsAfterTheBoxIsCleared() {
        let box = LockedBox<() -> Int>()
        box.value = { 42 }

        let taken = box.load()          // what the delivery site does
        box.value = nil                 // what the owner does, concurrently, on teardown

        XCTAssertNil(box.value, "the owner's clear really did take effect")
        XCTAssertEqual(taken?(), 42,
                       "and the in-flight call still completes — this is the "
                       + "use-after-free that #213 fixed, expressed deterministically")
    }

    /// The sharper form: prove the captured CONTEXT is retained, not merely that a
    /// pointer-sized value was copied. A closure capturing a class instance keeps that
    /// instance alive for as long as the loaded copy exists — which is exactly what the
    /// crashing code could not promise.
    func testTheLoadedCopyKeepsItsCapturedContextAlive() {
        final class Witness { var alive = true }
        weak var weakWitness: Witness?

        let box = LockedBox<() -> Bool>()
        var taken: (() -> Bool)?

        do {
            let witness = Witness()
            weakWitness = witness
            box.value = { witness.alive }
            taken = box.load()
            box.value = nil
        }   // the only other strong reference goes out of scope here

        XCTAssertNotNil(weakWitness,
                        "the loaded copy must be holding the captured object — if this "
                        + "is nil, a delivery in flight would be reading freed memory")
        XCTAssertEqual(taken?(), true)

        taken = nil
        XCTAssertNil(weakWitness, "and it is released once nothing holds it — no leak")
    }

    // MARK: - Plain semantics, so a rewrite cannot quietly change behaviour

    func testAnEmptyBoxLoadsNil_andSetThenGetRoundTrips() {
        let box = LockedBox<Int>()
        XCTAssertNil(box.load(), "a fresh box holds nothing")
        box.value = 7
        XCTAssertEqual(box.value, 7)
        XCTAssertEqual(box.load(), 7, "`value` and `load()` are the same read")
        box.value = nil
        XCTAssertNil(box.load())
    }

    func testTheInitialValueIsHeld() {
        XCTAssertEqual(LockedBox<Int>(3).value, 3)
        XCTAssertNil(LockedBox<Int>().value)
    }

    // MARK: - Concurrency: bounded, and honest about what it proves

    /// Hammer the box from several threads. This CANNOT prove the absence of a race —
    /// nothing at this level can, and a green threaded test is famously no evidence.
    /// It is here for the one thing it genuinely catches: a DEADLOCK. `load()`
    /// deliberately does not hold the lock across the caller's closure; if someone
    /// "tightens" it to do so, a callback that touches the box re-entrantly hangs.
    ///
    /// Two deliberate choices, both to keep the BLOCKING gate trustworthy:
    /// `concurrentPerform` rather than expectations — its closure is non-escaping, so
    /// there is no `Sendable` capture question to discover ten minutes later in CI, and
    /// no timeout knob to tune into flakiness. The cost is honest: a deadlock surfaces
    /// as a job timeout rather than a clean red test.
    func testConcurrentUseDoesNotDeadlock() {
        let box = LockedBox<() -> Int>()
        box.value = { 1 }

        DispatchQueue.concurrentPerform(iterations: 4) { worker in
            for i in 0..<2_000 {
                if worker == 0 {
                    // Written out rather than inline: a `nil` / closure-literal ternary
                    // leans on inference not worth a CI round to find out about.
                    let next: (() -> Int)? = (i % 3 == 0) ? nil : { i }
                    box.value = next
                } else {
                    _ = box.load()?()          // load, then call OUTSIDE the lock
                }
            }
        }

        box.value = { 5 }
        XCTAssertEqual(box.load()?(), 5, "the box still works after the hammering")
    }
}
