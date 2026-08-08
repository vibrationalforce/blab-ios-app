// AQuietPeerStopsLookingAliveTests.swift
// Echoel — #508. The frozen bio snapshot crossed the device boundary, 2.5× a second.
//
// WHAT WENT WRONG, on both ends of one protocol.
//
//   SENDER. `LiveColaboView`'s stream loop read `bus.latestBio` — the RAW snapshot, which
//   `EngineBus` never clears (its only writer is the publish sink; neither `stop()` nor a
//   lost pulse empties it, the very fact #503 is built on). Putting the phone down did not
//   stop the loop: it kept re-encoding the SAME frame every 400 ms for the rest of the
//   session, onto other people's screens, where it reads as a perfectly steady live pulse.
//
//   RECEIVER. `BioPeek` carries no time, and `peerBio[name]` was cleared ONLY on disconnect
//   or `stop()`. So a sender-only fix would have MOVED the defect rather than closed it —
//   worse, toggling "Share my pulse" off cancels the `.task` while the peer stays connected,
//   which froze their numbers on my screen forever WITHOUT any camera involved at all.
//
// ⭐ THIS IS #503/#507 ACROSS THE DEVICE BOUNDARY, and it is worse there for a reason worth
// naming: your own held pulse is at least yours, and the strip that shows it also says "No
// signal" beside it. A held PEER pulse is a claim about a body you cannot see, on a surface
// whose entire premise is "each person's own numbers, side by side".
//
// ⭐ AND IT IS THE ONLY BIO EGRESS PATH WITH THIS SHAPE — measured, not assumed.
// `ArtNetSender`, `SACNSender` and `ADMOSCSender` read the same raw snapshot, but all three
// end in `guard sourceTimestamp != lastFrameTimestamp`, so a frozen frame is a no-op for a
// light or a spatial object. The colab loop has no dedupe by design (unreliable transport: a
// receiver that missed the last packet still needs the next one), which is exactly what turns
// a frozen frame into a sustained broadcast.
//
// ⚠️ THE WINDOW IS NOT A COPY OF `BioSource.freshnessWindow`, and claim 5 pins that. It
// answers a DIFFERENT question: the sender already applied the freshness window to its own
// body before sending, so this one asks whether the NETWORK is still delivering. Reusing 6 s
// here would double-count one question and answer the other never. Honest total latency is
// therefore the SUM of the two windows, not the larger of them.
//
// ⚠️ WHICH HALF IS REAL BEHAVIOUR AND WHICH IS A SCAN — the limit first. Claims 4 and 5 drive
// shipped code end to end (`PeerReading` is `public` and Foundation-only). Everything else is
// a SOURCE SCAN: `LiveColaboView`'s rows are `private` structs behind
// `#if canImport(MultipeerConnectivity)` and `MultipeerSession` needs a real MC stack, so this
// bundle can prove where text is, never that a row renders. That a peer's row visibly blanks
// on a second device is a TWO-DEVICE check, and it is OPEN.
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING HERE, and that is MEASURED, not assumed (#484,
// #485 and #486 each had to retract the stronger claim). The retraction this slice writes into
// the stream loop quotes `bus.latestBio` verbatim to explain why that clock was wrong. Raw
// text on the fixed tree: 1×. Stripped: 0×. So claim 1's negative needle would be RED ON
// CORRECT CODE without the stripper — the #486/#491 collision again, this repo writes down
// what it removed.
//
// ⚠️ HONEST GRADING (#433), and it is the #464 situation said plainly rather than dressed up:
// this file CANNOT BE GRADED against the parent tree at all — claims 4 and 5 name
// `PeerReading`, which does not exist there, so the bundle does not compile and NO claim has a
// verdict. Transcribed by hand instead:
//   · claims 1, 2, 6, 7 — RED on the parent for their STATED reason (raw snapshot, literal
//     cadence, unstamped write, un-ticked rows).
//   · claims 4, 5 — could never have been red: they drive a type the same commit introduces.
//     Booking them as regressions would be the #433 defect in the flattering direction.
//   · claim 3 — green on BOTH trees. A true COUNTERWEIGHT, and the one that matters most: the
//     obvious later cleanup is "the frame is fresh now, drop the egress check", which would
//     ship a 5.1.3 violation. Freshness and PROVENANCE are different questions.
//   · claim 8 — red on the parent only because of the RENAME, not because the parent failed to
//     clear on disconnect. Said here rather than counted as a fifth regression (#427's lesson:
//     a signature-induced red is not a catch).

import Foundation
import XCTest
@testable import Echoelmusic

final class AQuietPeerStopsLookingAliveTests: XCTestCase {

    private static let view = "Sources/Echoelmusic/Studio/LiveColaboView.swift"
    private static let session = "Sources/Echoelmusic/Sync/MultipeerSession.swift"

    // MARK: - 1. The stream asks the freshness question

    func testTheStreamNoLongerSendsTheRawSnapshot() throws {
        let src = try code(at: Self.view)

        // #367: anchor FIRST. A bare "the token is absent" scan is green on a tree that lost
        // the whole loop — it would pass on an empty file.
        guard src.contains("colab.sendBio(BioPeek(") else {
            throw AnchorMissing(reason: """
                LiveColaboView no longer builds a BioPeek for the wire — the anchor for this \
                scan is gone. Re-anchor it; do not let the absence read as a pass.
                """)
        }
        XCTAssertTrue(
            src.contains("if let f = bus.usableBio(), BioEgressPolicy.allowsEgress(f.source),"),
            """
            The Colabo stream must gate on `bus.usableBio()` — the SOURCE's own freshness \
            window (#508) — before putting a body on the wire.
            """)
        XCTAssertEqual(
            occurrences(of: "bus.latestBio", in: src), 0,
            """
            The stream is reading `bus.latestBio` again (#508). `EngineBus` NEVER clears that \
            snapshot, and this loop has no dedupe, so a phone in a pocket keeps broadcasting \
            the same frozen frame 2.5× a second onto other people's screens — where it reads \
            as a live pulse.
            """)
    }

    // MARK: - 2. The cadence has one definition

    func testTheCadenceIsNotSpelledOutAtTheCallSite() throws {
        let src = try code(at: Self.view)
        XCTAssertTrue(
            src.contains("UInt64(PeerReading.sendInterval * 1_000_000_000)"),
            """
            The stream loop must sleep on `PeerReading.sendInterval` (#416/#508). The receiver's \
            staleness window is DERIVED from that constant, so a literal here would let the \
            cadence and the window drift apart silently — and the window is what decides when a \
            peer's row stops claiming a live body.
            """)
        XCTAssertEqual(
            occurrences(of: "400_000_000", in: src), 0,
            "The cadence literal is back at the call site; it belongs to `PeerReading` alone.")
    }

    // MARK: - 3. Counterweight: freshness did NOT absorb the 5.1.3 gate

    func testTheEgressGateSurvivesTheFreshnessGate() throws {
        let src = try code(at: Self.view)
        XCTAssertTrue(
            src.contains("BioEgressPolicy.allowsEgress(f.source)"),
            """
            The App Store 5.1.3 egress gate is gone from the Colabo stream. `usableBio()` does \
            NOT subsume it: freshness asks whether a reading is recent, provenance asks whether \
            it may leave the device at all. A HealthKit / Watch / ring frame is often perfectly \
            fresh — and streaming it to a nearby peer is exactly the violation the OSC and \
            ADM-OSC senders forbid.
            """)
    }

    // MARK: - 4. Behaviour: an arrived reading expires

    func testAnArrivedReadingStopsBeingLive() {
        let peek = BioPeek(bpm: 61, coherence: 0.42, hrvNormalized: 0.5, breathRate: 6)
        let r = PeerReading(peek: peek, arrivedAt: 1000)

        // Inside the window it is the reading, unchanged.
        XCTAssertEqual(r.live(at: 1000), peek)
        XCTAssertEqual(r.live(at: 1000 + PeerReading.staleAfter - 0.01), peek)

        // Past it, nothing — the row falls back to "—" rather than holding a stranger's pulse.
        XCTAssertNil(r.live(at: 1000 + PeerReading.staleAfter + 0.01))
        XCTAssertNil(r.live(at: 1000 + 600))

        // ⛔ THE FIRST DRAFT ASSERTED THE EXACT BOUNDARY AS `live(at: 1000 + staleAfter)` AND
        // WOULD HAVE BEEN RED ON CORRECT CODE — caught by transcribing the arithmetic before
        // committing, not by a reviewer. `1000 + 3.2` is not exact in `Double`, so subtracting
        // 1000 back out yields 3.2000000000000455, i.e. an age fractionally PAST the window.
        // The bound is closed, but that offset cannot demonstrate it. Same family as #442's
        // `slack` and #470's `+∞`: an assertion written from the algebra rather than from the
        // representation. Anchored at zero instead, where the subtraction is exact — and the
        // realistic cases above keep a margin, because both `arrivedAt` and `now` are wall-clock
        // reads that never land on the boundary anyway.
        let atZero = PeerReading(peek: peek, arrivedAt: 0)
        XCTAssertEqual(atZero.live(at: PeerReading.staleAfter), peek,
                       "The window is CLOSED at its upper bound — exactly stale is still shown.")
        XCTAssertNil(atZero.live(at: PeerReading.staleAfter.nextUp))

        // A schedule tick can land marginally BEHIND the arrival; that is skew, not staleness.
        // −1 s is the same allowance `EngineBus.usableBio()` grants its own frames — asked the
        // same way rather than minted a second time (#416/#426).
        XCTAssertEqual(r.live(at: 999.5), peek)
        XCTAssertEqual(r.live(at: 999.0), peek)
        XCTAssertNil(r.live(at: 998.9), "A clock that jumped backwards is not freshness.")

        // Non-finite makes every comparison false, so it reads as GONE. That is the safe
        // direction: blanking a row is cheaper than asserting a live person from a number
        // nothing can date.
        XCTAssertNil(r.live(at: .nan))
        XCTAssertNil(r.live(at: .infinity))
        XCTAssertNil(PeerReading(peek: peek, arrivedAt: .nan).live(at: 1000))
        XCTAssertNil(PeerReading(peek: peek, arrivedAt: .infinity).live(at: 1000))
    }

    // MARK: - 5. Behaviour: the window is DERIVED from the cadence, not chosen next to it

    func testTheStaleWindowIsDerivedFromTheSendCadence() {
        XCTAssertEqual(
            PeerReading.staleAfter, PeerReading.sendInterval * 8, accuracy: 1e-9,
            """
            The staleness window must stay eight missed sends (#508). Hardcoding it would let \
            a later cadence change leave a window tuned for a rate nobody sends any more — the \
            #416 shape, on the one number that decides when a peer stops looking alive.
            """)
        XCTAssertGreaterThan(
            PeerReading.staleAfter, PeerReading.sendInterval * 2,
            """
            The window must ride out ordinary drops. The transport is deliberately \
            `.unreliable`, so single losses are normal; a two-frame window would make every \
            row flicker on Wi-Fi jitter, which teaches people to ignore the blank.
            """)

        // NOT a copy of the bio freshness window — a different question, deliberately. If these
        // ever coincided, someone probably unified them, and the sum-of-two-windows reasoning
        // in the header would no longer hold.
        XCTAssertNotEqual(PeerReading.staleAfter, BioSource.cameraPPG.freshnessWindow)
    }

    // MARK: - 6. The receiver stamps arrival, on ITS clock

    func testTheReceiverStampsWhenTheFrameArrived() throws {
        let src = try code(at: Self.session)
        XCTAssertTrue(
            src.contains("public private(set) var peerReadings: [String: PeerReading]"),
            "MultipeerSession must store readings WITH their arrival time (#508).")
        XCTAssertTrue(
            src.contains("PeerReading(peek: peek,")
                && src.contains("arrivedAt: CFAbsoluteTimeGetCurrent())"),
            """
            The bio branch must stamp arrival with OUR clock. A sender-supplied field could not \
            report the failures that actually happen — a dropped link, a backgrounded app, a \
            peer that crashed — because a sender cannot tell you it stopped sending.
            """)
        XCTAssertEqual(
            occurrences(of: "var peerBio", in: src), 0,
            """
            An undated peer dictionary is back. It is the reason the defect existed: with a \
            bare `BioPeek` every reader has to invent its own answer to "is this peer still \
            sending?", and the honest answer is not derivable from the numbers.
            """)
    }

    // MARK: - 7. Both rows tick, and both ask the same question

    func testBothRowsExpireOnTheirOwnTick() throws {
        let src = try code(at: Self.view)

        guard let ownRow = block(startingAt: "private struct OwnBioRow: View {", in: src),
              let peerRows = block(startingAt: "private struct PeerBioRows: View {", in: src)
        else {
            throw AnchorMissing(reason: """
                OwnBioRow / PeerBioRows are no longer declared as their own structs in \
                LiveColaboView. They MUST stay leaf views — the bio reads are the 10.76.50 \
                freeze law, and a `TimelineView` needs a body that is allowed to churn.
                """)
        }

        // The own row shows exactly what the wire is being told — same question, both places.
        XCTAssertTrue(ownRow.contains("bus.usableBio()"),
                      "OwnBioRow must ask the same freshness question the stream loop asks.")
        XCTAssertTrue(ownRow.contains("TimelineView(.periodic(from: .now, by: 1))"), """
            OwnBioRow needs its own 1 Hz tick (#503, verbatim). `usableBio()` flips to nil on \
            the passage of TIME, and the event that makes it nil — a source that stopped \
            publishing — is the event that stops invalidating this body. Without a tick the row \
            freezes at the instant of the last frame and asserts liveness forever.
            """)

        XCTAssertTrue(peerRows.contains("PeerReading") || peerRows.contains("live(at:"),
                      "PeerBioRows must go through the reading, not the raw peek.")
        XCTAssertTrue(peerRows.contains(".live(at: CFAbsoluteTimeGetCurrent())"), """
            The peer row must resolve liveness when it RENDERS. A `TimelineSchedule` context \
            date is the SCHEDULED instant, and this body is rebuilt on every arrival, which \
            re-phases the schedule.
            """)

        // #503's placement, for #503's two reasons: one container where sibling rows belong,
        // and the rows would stop flattening into the enclosing VStack.
        guard let forEachAt = peerRows.range(of: "ForEach("),
              let tickAt = peerRows.range(of: "TimelineView(") else {
            return XCTFail("PeerBioRows lost either its ForEach or its tick.")
        }
        XCTAssertTrue(forEachAt.lowerBound < tickAt.lowerBound, """
            The tick moved OUTSIDE the ForEach. That puts ONE container where a list of sibling \
            rows belongs (#503) and the rows stop flattening into the enclosing VStack.
            """)

        // Counterweight to the obvious "just filter the dictionary" simplification: an expired
        // peer keeps its ROW and loses its NUMBERS. The peer is still CONNECTED, which is
        // information; dropping the row would shove the layout (#382) and make "went quiet"
        // look identical to "left the session".
        XCTAssertTrue(peerRows.contains("bpm: live?.bpm ?? 0"), """
            An expired peer must fall back to 0 — which `bioLine` already renders as "— bpm" — \
            not vanish from the list.
            """)
    }

    // MARK: - 8. Disconnect and stop still clear the readings

    func testLeavingStillRemovesThePeerEntirely() throws {
        let src = try code(at: Self.session)
        XCTAssertTrue(src.contains("peerReadings[name] = nil"), """
            A disconnected peer must be REMOVED, not merely expired (#508). Expiry says "still \
            here, gone quiet"; a peer who left is neither, and leaving their name on the board \
            would be a second kind of lie.
            """)
        XCTAssertTrue(src.contains("peerReadings.removeAll()"),
                      "stop() must clear every peer reading, as it always has.")
    }

    // MARK: - Helpers

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var search = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: search) {
            count += 1
            search = found.upperBound..<haystack.endIndex
        }
        return count
    }

    /// Brace-matched slice starting at `anchor` — so a claim about ONE declaration cannot be
    /// satisfied by text somewhere else in a 300-line file (the `TheVoiceIsOnTheBoardTests`
    /// form). Returns nil when the anchor is absent, so the caller can throw instead of
    /// passing vacuously (#367).
    private func block(startingAt anchor: String, in src: String) -> String? {
        guard let start = src.range(of: anchor) else { return nil }
        var depth = 0
        var idx = src.index(before: start.upperBound)   // the anchor's own "{"
        while idx < src.endIndex {
            let c = src[idx]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return String(src[start.lowerBound...idx]) }
            }
            idx = src.index(after: idx)
        }
        return nil
    }

    /// Comment-stripped source (#453 — the ONE definition of "code, not prose"). LOAD-BEARING
    /// here, measured: this slice's retraction comment names the token claim 1 forbids.
    private func code(at relativePath: String) throws -> String {
        let path = try treeRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The skip is scoped to the TREE, never to a file (#454): a per-file `fileExists` guard
    /// turns exactly the catastrophe this file watches for into a green skip.
    private func treeRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return root
    }

    private struct AnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }
}
