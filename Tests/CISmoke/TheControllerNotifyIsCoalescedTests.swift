// TheControllerNotifyIsCoalescedTests.swift
// Echoel — #951. Blocking bundle. END-TO-END BEHAVIOUR throughout, on a shipped,
// constructible type (`Tests/CISmoke/CLAUDE.md` §1): every claim drives the real
// `EngineBus.publish(controller:)` and counts what the real hook does.
//
// ⭐ THE DEFECT, AND `EngineBus` NAMED IT ITSELF BEFORE ANY GUARD DID. `publish(controller:)`
// spawned a `Task { @MainActor }` PER EVENT, and its own doc block says so and calls the
// repair a FOLLOW-UP: "coalesce the notification to once per batch — a pending flag here, or
// let `MIDIInput.drainIncoming` trigger the drain once after its loop. That collapses N tasks
// to one AND makes the hook non-redundant."
//
// It is the 10.76.48 shape exactly, and that one cost device builds: a high-rate source
// submitting one main-actor job per message starves the SwiftUI executor, and the symptom was
// an open `.menu` Picker that stopped responding. CLAUDE.md's rule is written for the camera
// ("never `Task { @MainActor }` per frame from a 30 fps source") — MIDI is the same shape from
// a source that can be FASTER: a fader bank or a wind controller on USB-MIDI sends thousands
// of messages a second, and #950 measured eleven CC streams (21–31) whose events nothing even
// consumes feeding straight into it.
//
// ⚠️ WHY COALESCING IS SAFE HERE, stated so a later session does not "restore" the per-event
// task as a fix for something: the drain consumes the QUEUE, whose order the single producer
// preserves, so whichever task runs first drains the whole backlog IN ORDER. `EngineBus`'s own
// doc says the per-task ordering "can only perturb the snapshot, which nothing reads" — and
// `latestControllerEvent` has no production reader (`git grep` finds the declaration, the one
// write, and two tests). So collapsing N tasks to one changes nothing a consumer can observe.
//
// ⚠️ THE ONE THING COALESCING CAN GET WRONG IS A LOST WAKE-UP, and claim 4 exists for it: if
// the pending flag is cleared AFTER the drain instead of before, an event enqueued mid-drain
// finds the flag still set, schedules nothing, and waits for the 10 Hz backstop poll — the
// exact latency #317 removed. ⛔ #951b: claim 4's FIRST version drove a second burst after the
// first had been delivered, which a clear-after implementation passes just as easily — the
// assertion could not fail for the reason its message gave (§2/#367). It now publishes from
// INSIDE the drain, the one interleaving that separates the two orderings. Found by the
// mandatory reviewer, and it is the same over-claim `ControllerEventDrainIsPushedTests`
// already retracted once in this area.
//
// ⚠️ HONEST GRADING. No local Swift toolchain (§0), so both implementations were transcribed
// and every assertion driven against each. **5 assertions.** Against the pre-#951 tree:
// **1 REGRESSION CATCH** — claim 1, the only one whose answer changes — and **4
// COUNTERWEIGHTS (#343)**. The file compiles against that tree (it uses no new API), so the
// catch is a real red there, not a build error. **0 broken, 0 red on the worktree.**
//
// ⚠️ NO NUMBER FROM `EngineBus` IS PINNED (#416): not the queue capacity, not a task count.
// Claim 1 asserts a RATIO against the burst it sent — "far fewer notifications than events" —
// so any coalescing implementation passes and a legitimate resize cannot redden it (#364).

import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class TheControllerNotifyIsCoalescedTests: XCTestCase {

    /// A reference box rather than a captured local `var`. `onControllerEventEnqueued` is an
    /// ESCAPING closure; mutating a captured local from one is the kind of thing Swift 6
    /// strict concurrency rejects, and there is no local toolchain to find that out cheaply
    /// (§0) — so the shape that cannot raise the question is the right one. Not `Sendable` and
    /// not required to be: the hook is `(@MainActor () -> Void)?` and this whole class is
    /// `@MainActor`, so the box never leaves the actor.
    private final class Counter { var n = 0 }

    private func event(_ i: Int) -> ControllerEvent {
        ControllerEvent(timestamp: Double(i), kind: .noteOn, channel: 1,
                        note: 60, value: 0.5, auxCC: 0)
    }

    /// Let every already-scheduled `Task { @MainActor }` run. A bounded loop rather than a
    /// single yield: the tasks are enqueued, not run inline, and one yield only guarantees one
    /// scheduling opportunity. Bounded so a hang is a FAILURE, never an infinite test.
    ///
    /// `until:` lets a caller that KNOWS what it is waiting for stop as soon as it arrives,
    /// instead of relying on a fixed count being generous enough — the shape
    /// `TheDemoSourceWakesWhenTheSensorStopsTests.publishAndSettle` already uses.
    ///
    /// ⚠️ DELIBERATELY NO `XCTFail` IN HERE (#416). Each caller's own assertion is the named
    /// failure, with the message that explains it; a second failure path inside the helper
    /// would report the same event twice and in vaguer words.
    private func settle(until reached: () -> Bool = { false }) async {
        for _ in 0..<40 {
            await Task.yield()
            if reached() { return }
        }
    }

    /// claim 1 (#951) — **THE FIX ITSELF.** A burst must announce itself a handful of times,
    /// not once per message.
    func testABurstNotifiesFarFewerTimesThanItHasEvents() async {
        let bus = EngineBus()
        let seen = Counter()
        bus.onControllerEventEnqueued = { seen.n += 1 }

        let burst = 50
        for i in 0..<burst { bus.publish(controller: event(i)) }
        await settle(until: { seen.n > 0 })

        XCTAssertGreaterThan(seen.n, 0, """
            precondition: the burst announced itself at least once. If this is 0 the hook \
            never fired at all and claim 1 below would pass for the wrong reason (#367).
            """)
        XCTAssertLessThan(seen.n, burst / 5, """
            \(burst) events produced \(seen.n) notifications — that is one \
            `Task { @MainActor }` per message, the shape CLAUDE.md bans for a 30 fps camera \
            and that MIDI can exceed. `EngineBus.publish(controller:)`'s own doc calls the \
            repair a follow-up: coalesce with a pending flag, cleared BEFORE the hook runs.

            The bound is deliberately loose (a fifth of the burst), not 1: any coalescing \
            implementation passes, and a scheduler that lets a few tasks interleave is not a \
            defect (#364).
            """)
    }

    /// claim 2 (COUNTERWEIGHT) — coalescing must not swallow events. The hook is a wake-up;
    /// the QUEUE is the payload, and it must still carry everything that was published.
    func testNoEventIsLostByCoalescing() async {
        let bus = EngineBus()
        bus.onControllerEventEnqueued = { }

        let burst = 50   // well under the ring's capacity, so nothing is dropped by design
        for i in 0..<burst { bus.publish(controller: event(i)) }
        await settle()

        var drained: [Double] = []
        while let e = bus.controllerEvents.dequeue() { drained.append(e.timestamp) }

        XCTAssertEqual(drained, (0..<burst).map(Double.init), """
            The queue did not carry every published event in order. Coalescing may only \
            collapse NOTIFICATIONS; the single-producer ring is what preserves order, and the \
            drain consumes it whole — that is the reason collapsing the tasks is safe at all.
            """)
    }

    /// claim 3 (COUNTERWEIGHT) — a SINGLE event must still be pushed. #317 exists because
    /// waiting for the 10 Hz backstop poll is worse than the latency it saves; a coalescing
    /// that only fires on the second event would quietly undo it.
    func testASingleEventStillNotifies() async {
        let bus = EngineBus()
        let seen = Counter()
        bus.onControllerEventEnqueued = { seen.n += 1 }

        bus.publish(controller: event(0))
        await settle(until: { seen.n > 0 })

        XCTAssertGreaterThan(seen.n, 0, """
            One published event announced nothing. The drain would then wait for the 10 Hz \
            poll backstop — the latency #317 removed. Coalescing collapses a burst; it must \
            never delay the first event.
            """)
    }

    /// claim 4 (COUNTERWEIGHT) — **NO LOST WAKE-UP, and it drives the ONE interleaving that
    /// can tell the two orderings apart.**
    ///
    /// ⛔ #951b — THE FIRST VERSION OF THIS CLAIM COULD NOT FAIL FOR THE REASON ITS MESSAGE
    /// GAVE. It published a second burst AFTER `await settle()`, i.e. after the first task had
    /// fully completed — at which point a clear-AFTER-the-hook implementation has also cleared
    /// the flag, so it was green there too. It detected only "the flag is never cleared at
    /// all", while its message and this file's header both claimed it caught the ORDERING.
    /// That is `Tests/CISmoke/CLAUDE.md` §2 / #367 exactly, and it is the same over-claim
    /// `ControllerEventDrainIsPushedTests` already retracted once in this very area ("a
    /// message must not claim more than its assertion"). Found by the mandatory reviewer.
    ///
    /// The discriminating interleaving is a publish from INSIDE the drain: with the flag
    /// cleared first, that publish schedules the next wake-up; with it cleared afterwards, the
    /// publish sees the flag still set, schedules nothing, and the event waits for the 10 Hz
    /// backstop poll.
    ///
    /// ⚠️ THIS IS A DEFENSIVE PROPERTY, NOT A LIVE HAZARD, and saying so is the point of the
    /// paragraph above. Today nothing can publish mid-drain: the only production producer is
    /// `MIDIBusPublisher` on the main actor, and the hook — `BioReactiveSynthVoice
    /// .drainControllerEvents` — does not publish. The ordering costs nothing and survives a
    /// future consumer that echoes; the claim pins the CHOICE, not a bug being fixed.
    func testAPublishFromInsideTheDrainSchedulesTheNextWakeUp() async {
        let bus = EngineBus()
        let seen = Counter()
        let midDrain = event(99)
        bus.onControllerEventEnqueued = { [weak bus] in
            seen.n += 1
            // Once only — this is the mid-drain enqueue, not a feedback loop.
            if seen.n == 1 { bus?.publish(controller: midDrain) }
        }

        bus.publish(controller: event(0))
        await settle(until: { seen.n > 1 })

        XCTAssertGreaterThan(seen.n, 1, """
            An event published WHILE the drain was running never announced itself. The pending \
            flag is being cleared AFTER the hook instead of before it: the mid-drain publish \
            finds it still set, schedules nothing, and the event waits for the 10 Hz backstop \
            poll — the latency #317 removed. Clear it FIRST; a redundant extra task is the \
            harmless direction.
            """)
    }
}
