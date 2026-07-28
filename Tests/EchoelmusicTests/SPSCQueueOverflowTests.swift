// SPSCQueueOverflowTests.swift
// The overflow branch of the one lock-free spine (#155).
//
// WHY THIS FILE EXISTS. `SPSCQueue` documents "Exactly ONE producer thread may call
// enqueue(), exactly ONE consumer thread may call dequeue()", and then `enqueue()`
// wrote the CONSUMER's `head` index on overflow to drop the oldest element. A producer
// cannot free a slot it does not own.
//
// THE FAILURE IS A LOST UPDATE. `dequeue()` publishes `head` with a plain store computed
// from a value it read earlier; two producer drops fit inside that window and the plain
// store then clobbers the producer's CAS. The result is a queue that reports EMPTY while
// holding live elements — `head` and `tail` meet with data still in the ring, so a
// `while let = dequeue()` drain reads "nothing pending" and the consumer starves.
//
// ⛔ A FIRST VERSION OF THIS HEADER CLAIMED A SECOND, SINGLE-THREADED FAILURE — that a
// lost CAS left `tail` behind `head` and mis-indexed the ring forever. Review refuted it
// and the correction is kept here on purpose: when the CAS loses, the producer still
// writes `tail = its own index + 1`, and the consumer can never reclaim that index, so
// the state is consistent. `count == capacity-1` is just what a full ring reads. The
// race needs a concurrent consumer.
//
// THE RACE IS LATENT, NOT OBSERVED. All three `enqueue()` queues are single-threaded end
// to end today (`bioFrames` has no consumer; `controllerEvents` and `bioEvents` have
// `@MainActor` producers AND consumers). It is closed because `EngineBus` declares these
// queues as having audio-thread consumers by design. Do not cite it as the cause of any
// shipped symptom.
//
// These tests pin the contract the fix restores: the producer never touches `head`, so
// an overflow drops the INCOMING element and says so — and an overflowed queue never
// claims to be empty.

import XCTest
@testable import Echoelmusic

final class SPSCQueueOverflowTests: XCTestCase {

    /// A power-of-two ring reserves one slot to tell "full" from "empty", so a queue
    /// built with capacity 4 holds 3. Pinned because every test below counts on it and
    /// because an off-by-one here reads as "the fix broke enqueue".
    func testUsableCapacity_isOneSlotLessThanTheRing() {
        let q = SPSCQueue<Int>(capacity: 4)
        XCTAssertTrue(q.enqueue(1))
        XCTAssertTrue(q.enqueue(2))
        XCTAssertTrue(q.enqueue(3))
        XCTAssertEqual(q.count, 3)
        XCTAssertTrue(q.isFull)
    }

    /// THE CONTRACT. A full queue rejects the new element instead of evicting the old
    /// one, because evicting means writing the consumer's index.
    func testEnqueue_whenFull_rejectsTheNewElement_insteadOfDroppingTheOldest() {
        let q = SPSCQueue<Int>(capacity: 4)
        XCTAssertTrue(q.enqueue(1))
        XCTAssertTrue(q.enqueue(2))
        XCTAssertTrue(q.enqueue(3))

        XCTAssertFalse(q.enqueue(99), "a full queue must report the drop, not claim success")

        // The three originals are still there, in order, and 99 never entered.
        XCTAssertEqual(q.dequeue(), 1)
        XCTAssertEqual(q.dequeue(), 2)
        XCTAssertEqual(q.dequeue(), 3)
        XCTAssertNil(q.dequeue())
    }

    /// The regression this file is really about: the OLD code advanced `head` here.
    /// Reading element 1 first is the observable proof that it no longer does.
    func testEnqueue_whenFull_leavesTheConsumerIndexAlone() {
        let q = SPSCQueue<Int>(capacity: 4)
        q.enqueue(1); q.enqueue(2); q.enqueue(3)
        let countBefore = q.count

        for extra in 100..<110 { XCTAssertFalse(q.enqueue(extra)) }

        XCTAssertEqual(q.count, countBefore, "overflow must not change how many elements are queued")
        XCTAssertEqual(q.dequeue(), 1, "the OLDEST element must survive — head belongs to the consumer")
    }

    /// THE FAILURE MODE THAT MOTIVATES THE WHOLE CHANGE: the lost-update race ended with
    /// `head == tail` and live data in the ring, i.e. a queue that answers "empty" while
    /// full. A single-threaded test cannot stage the interleaving, but it CAN pin the
    /// property the race violated — after any number of rejected enqueues the queue must
    /// still report exactly what it holds.
    func testOverflow_neverMakesTheRingClaimToBeEmpty() {
        let q = SPSCQueue<Int>(capacity: 4)
        q.enqueue(1); q.enqueue(2); q.enqueue(3)

        for extra in 0..<20 { XCTAssertFalse(q.enqueue(extra)) }

        XCTAssertFalse(q.isEmpty, "a full queue that rejected 20 elements is the opposite of empty")
        XCTAssertEqual(q.count, 3)
        XCTAssertTrue(q.isFull)
        XCTAssertNotNil(q.peek())
    }

    /// `droppedCount` is the only signal that a producer is outrunning its consumer.
    func testDroppedCount_countsEveryRejectedElement() {
        let q = SPSCQueue<Int>(capacity: 4)
        q.enqueue(1); q.enqueue(2); q.enqueue(3)
        XCTAssertEqual(q.droppedCount, 0)

        for extra in 0..<5 { q.enqueue(extra) }

        XCTAssertEqual(q.droppedCount, 5)
        XCTAssertEqual(q.enqueueCount, 3, "a rejected element is not an enqueue")
    }

    /// After a full queue is drained it must accept again — an overflow is a transient,
    /// not a permanent wedge. This is the test that would have failed on the corrupted
    /// ring described in the header (tail behind head → count stuck at capacity-1).
    func testQueue_recoversAfterOverflow_andKeepsFIFOOrderAcrossTheWrap() {
        let q = SPSCQueue<Int>(capacity: 4)
        q.enqueue(1); q.enqueue(2); q.enqueue(3)
        XCTAssertFalse(q.enqueue(4))

        XCTAssertEqual(q.dequeue(), 1)
        XCTAssertTrue(q.enqueue(4), "a freed slot must be usable again")

        XCTAssertEqual(q.dequeue(), 2)
        XCTAssertEqual(q.dequeue(), 3)
        XCTAssertEqual(q.dequeue(), 4, "the element added after the wrap must come last")
        XCTAssertTrue(q.isEmpty)
        XCTAssertEqual(q.count, 0)
    }

    /// `tryEnqueue` was ALREADY contract-correct (it never touched head). Pinned so the
    /// two paths cannot drift apart again — they now differ only in name.
    func testTryEnqueue_andEnqueue_agreeOnAFullQueue() {
        let a = SPSCQueue<Int>(capacity: 4)
        let b = SPSCQueue<Int>(capacity: 4)
        // `tryEnqueue` is NOT @discardableResult (SamplerVoice:416 discards it with an
        // explicit `_ =`), so the bare call would warn. The test target carries no
        // -warnings-as-errors — that flag is on the `Echoelmusic` target only
        // (Package.swift:28) — but a warning here is noise in every future run.
        for v in 1...3 { a.enqueue(v); _ = b.tryEnqueue(v) }

        XCTAssertFalse(a.enqueue(9))
        XCTAssertFalse(b.tryEnqueue(9))
        XCTAssertEqual(a.count, b.count)
        XCTAssertEqual(a.dequeue(), b.dequeue())
    }

    /// Many wraps in a row: catches an unmasked index or a lost slot that only shows up
    /// after the ring has turned over several times.
    func testRepeatedWraps_keepStrictFIFO() {
        let q = SPSCQueue<Int>(capacity: 8)   // 7 usable
        var expected = 0
        for v in 0..<200 {
            if !q.enqueue(v) {
                // Full: drain one, which must be the oldest outstanding value.
                XCTAssertEqual(q.dequeue(), expected)
                expected += 1
                XCTAssertTrue(q.enqueue(v), "a freed slot must accept the retry")
            }
        }
        while let got = q.dequeue() {
            XCTAssertEqual(got, expected)
            expected += 1
        }
        XCTAssertEqual(expected, 200, "every value must come out exactly once, in order")
    }
}
