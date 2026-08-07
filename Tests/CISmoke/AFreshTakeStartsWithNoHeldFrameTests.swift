// AFreshTakeStartsWithNoHeldFrameTests.swift
// Echoel — #454. `CameraRPPGBioPublisher.stop()` did not clear the three hold anchors, so a
// new take could begin by re-publishing the PREVIOUS take's frame, and — worse — could carry
// the previous take's COHERENCE on genuinely live frames.
//
// ⭐ THE TWO HALVES FAIL DIFFERENTLY, and only the second one is unmaskable.
//
//   1. `lastGoodBioFrame` + `lastGoodPublishTick`. `tick` is a LOCAL of `publishTask`, so a
//      new take restarts it at 0 while `lastGoodPublishTick` still held the previous take's
//      count. `tick - lastGoodPublishTick` was therefore hugely NEGATIVE — hence
//      `<= bioHoldTicks`, hence the dropout-hold branch fired from the very first tick of a
//      fresh take, re-emitting the previous take's frame for the whole re-acquisition window
//      (#415 measured ~19 s of that). This half is LARGELY masked downstream and the honest
//      statement says so: the held frame carries the previous take's own timestamp, so
//      `EngineBus.usableBio()` expires it after `BioSource.cameraPPG.freshnessWindow` (6 s),
//      timestamp-deduping consumers treat it as a no-op, and `EngineBus.latestBio` was never
//      cleared by a stop anyway. A restart more than 6 s after the last good frame costs
//      nothing measurable. It is still wrong — state named per-take that survives the take —
//      and it is the reachable path to the trap in claim 4.
//
//   2. `lastValidCoherence`, and this one is NOT on the hold path. The SUCCESS path publishes
//      `coherence.valid ? coherence.coherence : lastValidCoherence * 0.9` and writes the value
//      back ONLY when valid. At the start of a take there is not yet enough RR for a valid
//      coherence, so every genuinely live frame — new timestamp, real heart rate, passes every
//      freshness gate — carried the PREVIOUS take's coherence scaled once. Not a decay: a
//      CONSTANT, because the gated write-back never lowers it. Nothing downstream can catch
//      this; the frame really is fresh, only that one number belongs to a different take. The
//      comment on that line states the intent it violates — "hold coherence across TRANSIENT
//      invalidity" — and a stop/start is not transient.
//
// ⚠️ WHAT THIS FILE CANNOT DO, said first. Every assertion here is a SOURCE SCAN. The three
// fields are `private`, the publisher lives behind `#if canImport(AVFoundation)`, and driving
// it needs a camera — so there is no behavioural test to write, and the numbers above come
// from reading the code, not from a run. What is proven is that the assignments exist and that
// the premises the reasoning rests on are still true.
//
// ⚠️ AND IT WOULD NOT HAVE CAUGHT THE BUG ON ITS OWN. A scan can only assert the shape someone
// already decided on. The defect was an OMISSION in a method that resets ~20 other fields; no
// guard over the fields that WERE reset would have noticed. Claim 4 is the part that earns its
// place going forward, because it fails on a change nobody would connect to this file.

import Foundation
import XCTest
@testable import Echoelmusic

final class AFreshTakeStartsWithNoHeldFrameTests: XCTestCase {

    // MARK: - 1. the three anchors are cleared on stop

    /// RED before #454: `stop()` reset respiration, the settle state, the re-lock budget and a
    /// dozen more, and none of these three.
    func testStopClearsAllThreeHoldAnchors() throws {
        let body = try stopBody()
        for assignment in ["lastGoodBioFrame = nil",
                           "lastGoodPublishTick = Int.min",
                           "lastValidCoherence = 0"] {
            XCTAssertTrue(body.contains(assignment), """
                `CameraRPPGBioPublisher.stop()` no longer contains `\(assignment)`.

                These three are PER-TAKE state. Leaving any of them behind lets a new take \
                begin with the previous take's held frame, its tick anchor, or — the half \
                nothing downstream can mask — the previous take's coherence riding on \
                genuinely live frames until the RR series is long enough to be valid.

                Body scanned (comments blanked by SourceText.codeOnly):
                \(body)
                """)
        }
    }

    // MARK: - 2. the pair is restored to exactly the cold-start pair

    /// The declaration is what makes `Int.min` in `stop()` the RIGHT value rather than an
    /// arbitrary sentinel: the point is to restore the state a first-ever take begins in.
    /// If the declaration ever seeds something else, `stop()` stops matching it and the
    /// reasoning in claim 4 no longer holds.
    func testTheDeclarationStillSeedsTheSameSentinel() throws {
        let source = try publisherSource()
        XCTAssertTrue(source.contains("private var lastGoodPublishTick = Int.min"), """
            `lastGoodPublishTick` is no longer declared as `Int.min`.

            `stop()` resets it to `Int.min` in order to restore the exact cold-start pair \
            (nil frame + sentinel tick). A different seed makes those two states diverge, and \
            claim 4 below is an argument about that pair.
            """)
        XCTAssertTrue(source.contains("private var lastGoodBioFrame: BioSampleFrame?"), """
            `lastGoodBioFrame` is no longer the optional this pairing assumes.
            """)
    }

    // MARK: - 3. the coherence write-back is still gated (the premise of half 2)

    /// If the write-back ever becomes unconditional, the "constant, not a decay" reasoning in
    /// this file's header is stale and must be re-derived rather than trusted.
    func testTheCoherenceWriteBackIsStillGatedOnValidity() throws {
        let source = try publisherSource()
        XCTAssertTrue(
            source.contains("if coherence.valid { self.lastValidCoherence = coherence.coherence }"),
            """
            The gated coherence write-back is gone.

            This file's account of the defect depends on it: because the write-back only runs \
            when the window is VALID, an invalid start-of-take published \
            `lastValidCoherence * 0.9` unchanged on every frame. Make it unconditional and the \
            emitted value decays instead — a different (milder) defect, and the header here \
            would be describing code that no longer exists.
            """)
        XCTAssertTrue(source.contains("self.lastValidCoherence * 0.9"), """
            The success path no longer falls back to the held coherence.
            """)
    }

    // MARK: - 4. the counterweight: the short-circuit that keeps `Int.min` from trapping

    /// ⭐ THE ONE ASSERTION HERE THAT GUARDS SOMETHING NOBODY WOULD CONNECT TO THIS FILE.
    ///
    /// `Int.min` is a sentinel that sits inside a SUBTRACTION: `tick - lastGoodPublishTick`.
    /// With `tick` at 0 that is `0 - Int.min`, which OVERFLOWS and traps in Swift. The only
    /// thing that has ever prevented it is evaluation order — the optional binding
    /// `if let held = self.lastGoodBioFrame` comes FIRST and short-circuits, and the two
    /// fields are only ever `nil`/`Int.min` together.
    ///
    /// Swapping those two conditions reads like a harmless tidy-up and turns a fresh launch
    /// into a crash. This assertion is why it goes red instead.
    func testTheFrameBindingGuardsTheSentinelSubtraction() throws {
        let source = try publisherSource()
        guard let binding = source.range(of: "if let held = self.lastGoodBioFrame"),
              let subtraction = source.range(of: "tick - self.lastGoodPublishTick") else {
            return XCTFail("""
                The dropout-hold branch no longer has both of its anchors in the expected form.

                Looked for `if let held = self.lastGoodBioFrame` and \
                `tick - self.lastGoodPublishTick`. Anchoring on BOTH is deliberate: a scan that \
                only forbade the bad order would pass on a file that had lost the branch \
                entirely (#367).
                """)
        }
        XCTAssertTrue(binding.lowerBound < subtraction.lowerBound, """
            The sentinel subtraction is now evaluated BEFORE the optional binding.

            `tick - lastGoodPublishTick` with the cold-start sentinel is `0 - Int.min`, which \
            overflows and traps. Nothing else prevents it — the binding short-circuiting first \
            is the whole guarantee. Restore the order, or stop using `Int.min` as the sentinel.
            """)
    }

    // MARK: - source access

    /// Comment-stripped publisher source, or a skip when the tree is not present.
    ///
    /// Stripping via `SourceText.codeOnly` (#453) is load-bearing here rather than hygienic:
    /// the ⭐ block this slice added to `stop()` names all three identifiers, `Int.min` and
    /// `nil` in prose. Under a scanner that kept comments, every assertion in claim 1 would be
    /// satisfied by the comment explaining the fix — green on the exact code it is meant to pin.
    private func publisherSource() throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(
            "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The body of `public func stop()`, brace-matched.
    ///
    /// Brace-matched rather than "everything after the declaration": `stop()` happens to be the
    /// last method in the type today, and a scan that relied on that would silently widen to
    /// the whole file the day someone appends another one — the file-ORDER trap this repo has
    /// already paid for elsewhere.
    private func stopBody() throws -> String {
        let source = try publisherSource()
        guard let start = source.range(of: "public func stop() {") else {
            throw XCTSkip("`public func stop()` not found — the method was renamed or removed")
        }
        // `start.upperBound` sits just past the opening brace, so the depth starts at 1.
        var depth = 1
        var body = ""
        var i = start.upperBound
        while i < source.endIndex, depth > 0 {
            let c = source[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            body.append(c)
            i = source.index(after: i)
        }
        XCTAssertEqual(depth, 0, "unbalanced braces while extracting `stop()` — scan is unsound")
        return body
    }
}
