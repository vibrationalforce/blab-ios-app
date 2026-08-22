// TheHeldFrameSurvivesAResolutionFlipTests.swift
// Echoel — the door #730 built made a latent branch reachable. #732.
//
// WHAT WAS WRONG, AND WHY IT DID NOT EXIST BEFORE #730. `ArtNetSender.sendIfFresh` has a HOLD
// branch: with no fresh or allowed source it reuses `lastChannels` and keeps running the
// master/blackout/slew logic, so a Blackout is honoured even after bio stops. That is the L1
// law, written at the branch itself — "a stale/gated source must never freeze a blackout".
// The held array is sized for the resolution in force when it was built. While `resolution`
// had NO writer anywhere in the repository the two could never disagree; the moment #730 gave
// it a Picker, flipping mid-hold left one tick encoded with a stride the array does not have —
// 8-bit stride reading a 16-bit array lands on the dimmer-fine and red coarse/fine bytes.
//
// ⭐ THE REPAIR IS RE-ENCODE, NOT CLEAR, AND THE DIFFERENCE IS THE WHOLE POINT. Clearing
// `lastChannels` also looks correct and is what the finding was first registered with; it
// would send the hold branch down its `else { return }` path and FREEZE A BLACKOUT until the
// next fresh frame (~1 s at bio rate) — the exact failure the hold branch exists to prevent.
// A safety control that stops working for a second after an unrelated menu change is a worse
// defect than the cosmetic tick it would have fixed.
//
// ⚠️ THE LIMIT, STATED BEFORE THE CLAIM (§1). Claims 1-6 are END-TO-END BEHAVIOUR — they drive
// the shipped `static func` over real byte arrays, which is the strong kind. Claims 7-8 are a
// SOURCE-TEXT SCAN: the `didSet` and the hold branch sit on a `@MainActor` class whose network
// path no test bundle can exercise. That a physical 8-bit fixture reads the result correctly
// is a DEVICE PROBE and stays open.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file names `ArtNetSender.reencode`, which THIS
// commit creates, so it **does not compile against the parent `ad0a5cb` and no assertion has a
// verdict there** — saying that plainly, because #488 shipped a red gate for a cycle behind
// exactly this ambiguity. Hand-transcribed instead, in Python against BOTH trees — the parent
// is read too, because claim 7's regression verdict is a statement about the parent and the
// first version claimed only the worktree had been driven (#733):
//   · Claims 1-6 are FORWARD guards (#433). They could never have been red on the parent, and
//     booking them as regressions would be the flattering-direction defect. What makes them
//     worth writing is that they are arithmetic a CI round trip cannot check for me (#686):
//     the exactness claim was derived over all 256 byte values BEFORE the code was written,
//     not sampled, and re-derived against a deliberately wrong implementation (`b * 256`
//     instead of `b * 257`), which reds claim 1 for 255 of 256 inputs.
//   · ⛔ AND ONE MUTANT WALKED THROUGH ALL EIGHT (#733). A narrowing that simply TAKES THE
//     COARSE BYTE passed every claim in the first version of this file, because widening only
//     ever produces words of the form `[b, b]` and for those the coarse byte IS the correct
//     level — and claim 6's three vectors were all of that form. The lesson is narrower and
//     more useful than "behavioural beats source-text": a behavioural guard is only as strong
//     as its VECTORS. Claim 6 now carries pairs whose fine byte differs from the coarse one.
//   · ⚠️ CLAIMS 3 AND 4 ARE PROPERTY PINS, NOT GUARD-CLAUSE PINS, and say so rather than
//     implying more (#733). Delete `old != new` from `reencode` and claim 3 stays green (the
//     `default:` arm returns the input anyway); delete `!channels.isEmpty` and claim 4 stays
//     green (an empty loop appends nothing). They pin the observable PROPERTY — idempotent
//     write, unlit rig stays unlit — which is what a caller depends on. They do not prove the
//     early return exists, and the first version's messages read as if they did.
//   · Claim 7 is a REGRESSION: the parent has no `didSet` on either sender.
//   · Against `023cbf2` — #733's own parent — **all eight are green**: that slice is a prose
//     and VECTOR repair, not a behaviour change, and the vectors are why it was worth doing.
//     Re-driven on both trees; claim 7 red on `ad0a5cb` for BOTH senders, claim 8 green on all
//     three trees for both.
//   · Claim 8 is a COUNTERWEIGHT, green on both — and it is the load-bearing one. If the hold
//     branch is ever removed, the `didSet` becomes dead weight and the long note on
//     `ArtNetSender.resolution` becomes false; this claim is what forces both to move (#456).
//
// ⚠️ NO STRIPPER MEASUREMENT IS OWED FOR CLAIMS 1-6 — they read no source text at all. For the
// two that do, `SourceText.codeOnly` is **PROPHYLAKTISCH (0 of 2)**, measured: both needles are
// long enough that no comment contains them — raw 1, code 1, at each of the FOUR needle sites
// across TWO scanned files (each claim now reads both senders). (⛔ The first version said "in
// all three files"; only two files are scanned, and at that point one of the two claims read
// only one of them — #733.)
//
// ⛔ THE FIRST DRAFT OF THIS PARAGRAPH CLAIMED `TRAGEND (1 of 2)` AND WAS CAUGHT BY MEASURING
// IT BEFORE THE COMMIT, NOT AFTER — the third slice in a row to write a stripper label from
// intuition (#728 in the flattering direction, #731 in the other). What made it plausible is
// TRUE and is the reason the stripper stays: in `ArtNetSender.swift` the BARE name
// `lastChannels` now reads 8 raw against 6 in code, because #732's own doc note on
// `resolution` explains the hold branch there (the sACN note points at it instead). A future
// slice that shortens either needle to the bare name inherits a real flip. The label describes
// the needles that are actually written, not the ones that could be.

#if canImport(Network)
import XCTest
@testable import Echoelmusic

private struct FlipAnchorMissing: Error, CustomStringConvertible {
    let reason: String
    var description: String { "anchor missing: \(reason)" }
}

@MainActor
final class TheHeldFrameSurvivesAResolutionFlipTests: XCTestCase {

    private static let artNet = "Sources/Echoelmusic/Sync/ArtNetSender.swift"
    private static let sacn = "Sources/Echoelmusic/Sync/SACNSender.swift"

    // MARK: - 1 · the 8-bit → 16-bit → 8-bit round trip is exact for EVERY byte

    func testEveryByteSurvivesTheRoundTripExactly() {
        let all: [UInt8] = (0...255).map { UInt8($0) }
        let wide = ArtNetSender.reencode(all, from: .eightBit, to: .sixteenBit)
        let back = ArtNetSender.reencode(wide, from: .sixteenBit, to: .eightBit)
        XCTAssertEqual(back, all, """
            The 8-bit → 16-bit → 8-bit round trip is no longer exact.

            It is exact by arithmetic, not by luck: 65535 / 255 == 257, so byte `b` becomes the
            word `b * 257` — coarse `b`, fine `b` — and reading it back yields `b` again. An
            implementation using `b * 256`, or one that drops the fine byte, reds this for 255
            of the 256 inputs. This is checked over ALL of them, not a sample, because a CI run
            is a lottery ticket and not a check on arithmetic (#686).
            """)
    }

    /// 1b — the exactness is a property of the WORD, not only of the round trip: a byte must
    /// land on coarse == fine == b. Without this, a symmetric-but-wrong pair of conversions
    /// (both scaling by 256) would pass claim 1 while sending a fixture the wrong level.
    func testAByteWidensToCoarseAndFineOfItself() {
        for b in [UInt8(0), 1, 42, 128, 254, 255] {
            let wide = ArtNetSender.reencode([b], from: .eightBit, to: .sixteenBit)
            XCTAssertEqual(wide, [b, b], """
                Byte \(b) widened to \(wide) instead of [\(b), \(b)]. 16-bit DMX is
                coarse(MSB)+fine(LSB) over 65 535 steps, and `b * 257` is the only widening
                that both round-trips and puts the same physical level on the fixture.
                """)
        }
    }

    // MARK: - 2 · the length is the stride the hold branch assumes

    func testWideningDoublesAndNarrowingHalvesTheArray() {
        let four: [UInt8] = [10, 20, 30, 40]
        XCTAssertEqual(ArtNetSender.reencode(four, from: .eightBit, to: .sixteenBit).count, 8, """
            8-bit → 16-bit no longer doubles the channel count. The whole defect this repairs is
            a held array whose LENGTH disagrees with the stride `applyDimmer` and
            `applySlewedColour` use; a conversion that keeps the old length fixes nothing.
            """)
        let eight: [UInt8] = [0, 0, 1, 1, 2, 2, 3, 3]
        XCTAssertEqual(ArtNetSender.reencode(eight, from: .sixteenBit, to: .eightBit).count, 4, """
            16-bit → 8-bit no longer halves the channel count — see above, in the other
            direction.
            """)
    }

    // MARK: - 3 · no churn when nothing changed

    func testTheSameResolutionIsIdentity() {
        let bytes: [UInt8] = [7, 8, 9, 10]
        XCTAssertEqual(ArtNetSender.reencode(bytes, from: .eightBit, to: .eightBit), bytes, """
            Re-encoding to the SAME resolution changed the array. The `didSet` fires on every
            write, including a Picker tap that re-selects the current value, so this must be a
            no-op — otherwise an idempotent user action degrades the held colour.
            """)
        XCTAssertEqual(ArtNetSender.reencode(bytes, from: .sixteenBit, to: .sixteenBit), bytes)
    }

    // MARK: - 4 · an unlit rig stays unlit

    func testAnEmptyHoldStaysEmpty() {
        XCTAssertEqual(ArtNetSender.reencode([], from: .eightBit, to: .sixteenBit), [], """
            An empty held array must stay empty. `sendIfFresh` gates the hold branch on
            `!lastChannels.isEmpty`, so inventing bytes here would make a rig that was never lit
            start emitting on a menu change.
            """)
    }

    // MARK: - 5 · a malformed odd-length array must not trap

    func testAnOddLengthSixteenBitArrayDropsTheTrailingByteInsteadOfTrapping() {
        let odd: [UInt8] = [1, 2, 3]
        let out = ArtNetSender.reencode(odd, from: .sixteenBit, to: .eightBit)
        XCTAssertEqual(out.count, 1, """
            An odd-length 16-bit array produced \(out.count) bytes. The shipped encoders cannot
            emit one, so this is defence, not a scenario — but the pairing loop reads
            `channels[i + 1]`, and an out-of-bounds read here would crash the app on a menu tap.
            The trailing half-word is dropped.
            """)
    }

    // MARK: - 6 · the narrowing is the real physical level

    /// ⛔ THE FIRST VERSION USED ONLY `[b, b]` WORDS AND DISCRIMINATED NOTHING (#733). Its
    /// three vectors were 0xFFFF, 0x0000, 0x8080 and its message claimed a conversion that
    /// "merely TOOK the coarse byte" would fail claim 1 elsewhere. Measured, BOTH halves are
    /// false: for every word of the form `[b, b]` the correct narrowing IS `b`, and widening
    /// produces only that form — so a coarse-byte implementation passed claim 1, claim 1b,
    /// claim 2, claim 3, claim 4, claim 5 AND claim 6. The whole file was green against a
    /// mutant. #367 in its stated mirror form, and the reason a behavioural guard is not
    /// automatically a strong one: the VECTORS decide, not the technique.
    /// The pairs below have a fine byte that differs from the coarse one, which is the only
    /// shape that can tell the two implementations apart.
    func testNarrowingReturnsTheLevelTheWordRepresents() {
        let cases: [(word: [UInt8], level: UInt8, coarse: UInt8)] = [
            ([0x01, 0x00], 0, 1),
            ([0x40, 0x00], 63, 64),
            ([0xFF, 0x00], 254, 255),
            ([0xFF, 0xFF], 255, 255)
        ]
        for c in cases {
            let out: [UInt8] = ArtNetSender.reencode(c.word, from: .sixteenBit, to: .eightBit)
            XCTAssertEqual(out, [c.level], """
                Word \(c.word) narrowed to \(out) instead of [\(c.level)]. It must return the
                LEVEL the 16-bit word represents. Taking the coarse byte would give \(c.coarse)
                here — that is the mutant this vector exists to kill, and the three `[b, b]`
                vectors the first version used could not see it.
                """)
        }
    }

    // MARK: - 7 · REGRESSION: one control, both protocols — both senders re-encode

    func testBothSendersReEncodeOnAResolutionChange() throws {
        for path in [Self.artNet, Self.sacn] {
            let code: String = try codeOf(path)
            XCTAssertTrue(code.contains("reencode(lastChannels, from: oldValue, to: resolution)"), """
                \(path) no longer re-encodes its held channels when `resolution` changes.

                One Picker drives BOTH senders (#730), so a `didSet` on only one of them splits
                the rig: one protocol re-encodes its hold, the other keeps emitting at the old
                stride. If you replaced re-encoding with CLEARING, read the note on
                `ArtNetSender.resolution` first — clearing freezes a blackout for up to a second,
                which is the L1 failure the hold branch exists to prevent.
                """)
        }
    }

    // MARK: - 8 · COUNTERWEIGHT: the hold branch this all protects still exists

    /// ⛔ IT LOOPS BOTH SENDERS (#733). The first version scanned Art-Net only while claim 7
    /// already looped both, so removing sACN's hold branch left this green while sACN's
    /// `didSet` became dead weight and its doc pointer became false — exactly the #456
    /// movement this claim exists to force, missed in the claim that names #456.
    func testTheHoldBranchStillExists() throws {
        for path in [Self.artNet, Self.sacn] {
            let code: String = try codeOf(path)
            XCTAssertTrue(code.contains("channels = lastChannels"), """
                \(path) no longer holds its last channels in `sendIfFresh`.

                Then that sender's `didSet` is dead weight and the note on `resolution` \
                describes a branch that is gone — both must move in the SAME commit (#456). \
                This is the claim that makes claims 1-7 mean something: without the hold \
                branch there is nothing to re-encode, and a green claim 7 would be guarding a \
                repair with no defect left.
                """)
        }
    }

    // MARK: - helpers

    private func codeOf(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw FlipAnchorMissing(reason: """
                \(relativePath) is not present while `Sources/` is — the anchor moved. A missing
                TREE skips (see `repoRoot`); a missing ANCHOR fails (#454)
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }
}
#endif
