// PanicFanOutTests.swift
// Echoel — the performance panic must reach EVERY voice it is given (#160, #168).
//
// #160's defect: the panic button released three of eight note-producing voices while
// its accessibility hint promised "every sounding note on every voice". #160 fixed the
// list; the review's HIGH was that nothing could ever fail if the list regressed, because
// the fan-out was `private` on a `View`. This file is that missing failure mode.
//
// ⚠️ WHAT THESE TESTS DO NOT PROVE, stated up front so a green run is not over-read: they
// pin that every target HANDED to `PanicFanOut` is released, in order. They cannot see a
// voice that `EchoelStudioView.panicAllNotesOff()` never puts in the array — that
// inventory has no test and is guarded by a comment at the call site. Narrowing the
// untested surface to one line is the win here, not eliminating it.

import XCTest
@testable import Echoelmusic

/// FILE SCOPE and explicitly `@MainActor`, both deliberately. Nesting these inside the
/// `XCTestCase` would leave them relying on inherited isolation, and nested types do NOT
/// inherit a global actor — the two toolchains in use here disagree about the consequences
/// (SwiftPM's test target is Swift 5 without strict concurrency; the Xcode gate is Swift 6),
/// so a nested spy is exactly the shape that compiles in one gate and fails the other. That
/// mismatch has already cost a red gate on this repo (#142).
@MainActor
private final class ReleaseLog {
    var order: [String] = []
}

/// Records that it was released, and WHEN relative to its siblings — order is part of the
/// contract, not an implementation detail (see `testReleasesInOrder`).
@MainActor
private final class SpyVoice: NoteReleasable {
    let name: String
    private(set) var releaseCount = 0
    private let log: ReleaseLog

    init(_ name: String, log: ReleaseLog) { self.name = name; self.log = log }
    func releaseAllNotes() {
        releaseCount += 1
        log.order.append(name)
    }
}

@MainActor
final class PanicFanOutTests: XCTestCase {

    func testReleasesEveryTargetExactlyOnce() {
        let log = ReleaseLog()
        let voices = (0..<8).map { SpyVoice("v\($0)", log: log) }
        // Explicitly typed: `[SpyVoice]` → `[NoteReleasable?]` is TWO implicit conversions
        // (existential upcast + optional wrapping) and is not worth relying on.
        let targets: [NoteReleasable?] = voices
        let released = PanicFanOut(targets).releaseAll()

        XCTAssertEqual(released, 8, "every target reports as released")
        for v in voices {
            XCTAssertEqual(v.releaseCount, 1, "\(v.name) released exactly once")
        }
    }

    /// ORDER IS THE CONTRACT, not a detail. `PianoRollModel` must be released FIRST because
    /// its release also clears the roll's `active` note table; run it later and the roll's
    /// next tick issues a pitch-matched `noteOff` that can cut a note the performer
    /// retriggered AFTER the panic — a "release everything" that leaves an instrument
    /// swallowing the next note. A `Set`-based or concurrent fan-out would break this
    /// silently, which is why it is pinned rather than assumed.
    func testReleasesInOrder() {
        let log = ReleaseLog()
        let roll = SpyVoice("roll", log: log)
        let rest = ["synth", "sub", "lead", "midi"].map { SpyVoice($0, log: log) }
        let targets: [NoteReleasable?] = [roll] + rest
        PanicFanOut(targets).releaseAll()

        XCTAssertEqual(log.order, ["roll", "synth", "sub", "lead", "midi"])
    }

    /// The two play-surface voices are optional environment values that are genuinely
    /// absent until their surfaces exist. A nil must be SKIPPED — not crash, and not stop
    /// the fan-out at the first hole, which would silently spare every voice after it.
    func testNilTargetsAreSkipped_withoutStoppingTheFanOut() {
        let log = ReleaseLog()
        let first = SpyVoice("first", log: log)
        let last = SpyVoice("last", log: log)
        let targets: [NoteReleasable?] = [first, nil, nil, last]
        let released = PanicFanOut(targets).releaseAll()

        XCTAssertEqual(released, 2, "the count reports voices reached, not slots offered")
        XCTAssertEqual(log.order, ["first", "last"], "a hole does not end the fan-out")
    }

    /// Degenerate but real: an environment with nothing in it must be a no-op returning 0,
    /// never a crash. The count is what lets a caller tell "panic reached six voices" from
    /// "panic reached none" — the two look identical from the outside otherwise.
    func testEmptyAndAllNilFanOutsAreNoOps() {
        XCTAssertEqual(PanicFanOut([]).releaseAll(), 0)
        XCTAssertEqual(PanicFanOut([nil, nil]).releaseAll(), 0)
    }

    /// Panic is a control a performer may hit twice in a second. Releasing an already-
    /// released voice must stay a plain repeat, with no accumulated state in the fan-out
    /// (it holds the targets, so a second call must reach all of them again).
    func testFanOutIsReusable() {
        let log = ReleaseLog()
        let v = SpyVoice("v", log: log)
        let fanOut = PanicFanOut([v])   // one element: no array-covariance question

        fanOut.releaseAll()
        fanOut.releaseAll()
        XCTAssertEqual(v.releaseCount, 2)
    }
}
