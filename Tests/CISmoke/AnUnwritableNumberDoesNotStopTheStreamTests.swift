//
//  AnUnwritableNumberDoesNotStopTheStreamTests.swift
//  Echoelmusic — CISmoke (#512)
//
//  ⚠️ LIMITS FIRST. Almost everything here is REAL BEHAVIOUR driven end to end: `BioPeek`,
//  `BioSampleFrame`, `BioSource` and `ColabPayload` are all `public` Foundation-only value
//  types, so the coercion, the projection and the shipped `JSONEncoder` really run. Exactly
//  ONE assertion is a source scan. **That two phones actually keep exchanging numbers
//  through a bad rPPG sample is a two-device check and OPEN** — the same one #508 and #511
//  already have outstanding.
//
//  ⭐ WHAT THIS IS ABOUT. `ColabPayload.encoded()` is `try? JSONEncoder().encode(self)`, and
//  `JSONEncoder`'s default `nonConformingFloatEncodingStrategy` is `.throw`. So ONE
//  non-finite channel made the whole payload fail to encode, `try?` turned the throw into
//  `nil`, and `send` returned having done nothing — for as long as the source kept producing
//  it. Since #508 the peer's row blanks after eight missed sends, so on the other screen that
//  is indistinguishable from the network going quiet: **a single bad sample took FOUR good
//  numbers off someone else's display and kept them off.** The direction was safe. The cause
//  was misreported, and nothing anywhere said so.
//
//  ⭐ THE FIX IS ON THE MEMBERWISE `init`, NOT IN THE FACTORY, and two assertions exist only
//  to hold it there. `BioPeek` is `public` with that init; a hand-built peek reaches
//  `encoded()` with nothing on the wire path to notice. That is the same hole #511 closed for
//  PROVENANCE, closed here for FINITENESS — and the two stay separate on purpose (#416): one
//  asks which source may leave the phone, the other whether a number can be written down at
//  all. `testAHandBuiltPeekIsAlsoWritable` is what makes "on the init" a fact rather than a
//  preference.
//
//  ⚠️ HONEST GRADING (#433). Against the parent tree this file COMPILES — it names no symbol
//  #512 adds — so every assertion really has a verdict there, unlike the #464 situation.
//  Hand-transcribed and run: **THREE are regressions** (the encode sweep, the
//  reads-as-not-available sweep, the hand-built peek) and they are ONE finding reported three
//  ways, not three findings (#486) — one coercion, absent, observed at three call shapes.
//  **FOUR are counterweights, green on both trees**, and they are the content: they block the
//  three obvious later "cleanups" — clamp to a plausible range here, drop the peek instead of
//  the channel, reorder the 5.1.3 gate behind the finiteness one, or reach for
//  `.convertToString` on the encoder.
//
//  ⛔ `SourceText.codeOnly` IS LOAD-BEARING HERE, and the first draft of this header claimed
//  PROPHYLACTIC — the exact over-claim #484 and #485 each had to retract once and #486 twice,
//  repeated in the file that cites them, and contradicted two sentences later by its own
//  prose. MEASURED before committing: `nonConformingFloatEncodingStrategy` appears in
//  `ColabPayload.swift` **raw 1 / stripped 0** on this tree, because #512's own doc comment on
//  `BioPeek.init` names the strategy in order to explain the defect. **The negative scan below
//  would be RED ON CORRECT CODE without the stripper.** The #486/#491 collision, arrived at
//  the moment it was predicted: this repo writes down what it removed, so a negative scan
//  eventually lands on its own explanation. (On the parent tree the needle is 0/0 — the
//  collision is created BY the fix, not inherited.)
//

import XCTest
@testable import Echoelmusic

final class AnUnwritableNumberDoesNotStopTheStreamTests: XCTestCase {

    // MARK: - The defect (real behaviour, end to end through the shipped encoder)

    /// REGRESSION. A non-finite value in ANY of the four channels must not stop the payload
    /// from encoding — and the OTHER three must survive intact. The round-trip is the half
    /// that matters: a "fix" that dropped the whole `bio` field when one channel went bad
    /// would keep a bare non-nil check green while taking all four numbers off the peer's
    /// screen, which is the very defect (#343).
    func testANonFiniteChannelDoesNotStopThePayload() throws {
        let bad: [Float] = [.nan, .infinity, -.infinity]
        for value in bad {
            for channel in Channel.allCases {
                let f = frame(source: .cameraPPG, channel: channel, value: value)
                let peek = try XCTUnwrap(BioPeek.egressible(from: f), """
                    `.cameraPPG` may share, so the projection must produce a peek even when \
                    \(channel) is \(value).
                    """)
                let data = try XCTUnwrap(ColabPayload(kind: "bio", senderName: "me", bio: peek)
                                            .encoded(), """
                    A `\(value)` in \(channel) stopped the whole payload from encoding. \
                    `JSONEncoder`'s default non-conforming strategy is `.throw` and \
                    `encoded()` is a `try?`, so the send silently does nothing for as long \
                    as the source keeps producing it — which on the peer's screen reads as \
                    the network going quiet (#508), not as one missing number (#512).
                    """)
                let back = try XCTUnwrap(ColabPayload.decode(data)?.bio, """
                    The payload encoded but carries no bio reading. Dropping the peek when \
                    one channel is unwritable blanks the peer's whole row — it asserts the \
                    network stopped, which is false and the worse of the two lies.
                    """)
                for other in Channel.allCases where other != channel {
                    XCTAssertEqual(other.read(back), other.goodValue, accuracy: 1e-5, """
                        \(other) did not survive a bad \(channel). The three good numbers \
                        are the entire reason this is a per-channel coercion.
                        """)
                }
            }
        }
    }

    /// REGRESSION. The coerced channel is exactly `0`, which is this type's documented "not
    /// available" and what `bioLine` renders as "— bpm" / "coherence not available".
    func testANonFiniteChannelReadsAsNotAvailable() throws {
        for channel in Channel.allCases {
            let peek = try XCTUnwrap(
                BioPeek.egressible(from: frame(source: .ble, channel: channel, value: .nan)))
            XCTAssertEqual(channel.read(peek), 0, """
                A non-finite \(channel) must become `0`. `BioPeek` documents `0` as "not \
                available" and the peer row already renders it as a dash — anything else \
                would be a number nobody measured.
                """)
        }
    }

    /// REGRESSION, and the reason the coercion sits on the memberwise `init` rather than
    /// inside `BioPeek.egressible(from:)`. `BioPeek` is `public`; a peek built by hand never
    /// touches the factory, and nothing further down the wire path can notice.
    func testAHandBuiltPeekIsAlsoWritable() throws {
        let peek = BioPeek(bpm: .nan, coherence: 0.5, hrvNormalized: .infinity, breathRate: 6)
        XCTAssertEqual(peek.bpm, 0)
        XCTAssertEqual(peek.hrvNormalized, 0)
        XCTAssertNotNil(ColabPayload(kind: "bio", senderName: "me", bio: peek).encoded(), """
            A hand-built `BioPeek` still carries a value JSON cannot write. Moving the \
            coercion into `egressible(from:)` would pass every other assertion in this file \
            and leave exactly this hole open.
            """)
    }

    // MARK: - Counterweights

    /// COUNTERWEIGHT. The obvious later "tidy-up" is to clamp here to a plausible range while
    /// the hand is in. That would invent a number the body never produced — the mistake
    /// #424/#426/#433 each had to undo. This init answers ONE question: can it be written
    /// down. A negative or absurd FINITE reading travels untouched, and whether it is
    /// plausible is a question for whoever measured it.
    func testFiniteNumbersAreNotClamped() {
        let peek = BioPeek(bpm: -42.5, coherence: 3.25, hrvNormalized: 0.0001, breathRate: 1e30)
        XCTAssertEqual(peek.bpm, -42.5)
        XCTAssertEqual(peek.coherence, 3.25)
        XCTAssertEqual(peek.hrvNormalized, 0.0001)
        XCTAssertEqual(peek.breathRate, 1e30)
    }

    /// COUNTERWEIGHT. Provenance is still decided FIRST and independently. A frame that may
    /// not leave the device must produce no peek at all, however writable its numbers are —
    /// and a HealthKit frame carrying a NaN must not become sendable as a side effect of
    /// #512 (App Store 5.1.3).
    func testProvenanceIsStillDecidedIndependently() {
        for source in [BioSource.healthKit, .watch, .oura] {
            XCTAssertNil(BioPeek.egressible(from: frame(source: source,
                                                        channel: .bpm, value: .nan)), """
                A \(source) frame produced a peer payload. Finiteness and provenance are \
                different questions and #511's gate must run regardless of #512's.
                """)
            XCTAssertNil(BioPeek.egressible(from: frame(source: source,
                                                        channel: .bpm, value: 61)), """
                A \(source) frame with perfectly ordinary numbers produced a peer payload. \
                5.1.3 does not depend on the values.
                """)
        }
    }

    /// COUNTERWEIGHT (#343). Everything above stays green on a tree where sharing was ripped
    /// out or the bio kind stopped carrying numbers. Pin that an ordinary reading still makes
    /// it onto the wire with all four channels intact.
    func testAnOrdinaryReadingStillTravelsWhole() throws {
        let f = frame(source: .cameraPPG, channel: .bpm, value: 61.5)
        let peek = try XCTUnwrap(BioPeek.egressible(from: f))
        let data = try XCTUnwrap(ColabPayload(kind: "bio", senderName: "me", bio: peek).encoded())
        let back = try XCTUnwrap(ColabPayload.decode(data)?.bio)
        XCTAssertEqual(back.bpm, 61.5, accuracy: 1e-5)
        XCTAssertEqual(back.coherence, Channel.coherence.goodValue, accuracy: 1e-5)
        XCTAssertEqual(back.hrvNormalized, Channel.hrv.goodValue, accuracy: 1e-5)
        XCTAssertEqual(back.breathRate, Channel.breath.goodValue, accuracy: 1e-5)
    }

    /// COUNTERWEIGHT, and the one source scan. The OTHER way to stop the encoder throwing is
    /// `nonConformingFloatEncodingStrategy = .convertToString(...)`, and it is worse than the
    /// defect: it writes a STRING where every shipped receiver expects a number, and their
    /// `JSONDecoder` default is `.throw` too — so an older peer would drop the whole payload,
    /// project shares included. The wire format is a compatibility promise; sanitising the
    /// value is not.
    func testTheEncoderKeepsItsDefaultFloatStrategy() throws {
        let text = try source("Sources/Echoelmusic/Sync/ColabPayload.swift")
        XCTAssertFalse(text.contains("nonConformingFloatEncodingStrategy"), """
            `ColabPayload` sets a non-conforming float strategy on its encoder. That changes \
            the WIRE FORMAT for every receiver that already exists — a peer on an older build \
            decodes with `.throw` and loses the entire payload, not just one channel. Coerce \
            the value at the type instead (#512).
            """)
    }

    // MARK: - Fixtures

    fileprivate enum Channel: CaseIterable, CustomStringConvertible {
        case bpm, coherence, hrv, breath

        var description: String {
            switch self {
            case .bpm: return "heart rate"
            case .coherence: return "coherence"
            case .hrv: return "HRV"
            case .breath: return "breath rate"
            }
        }

        /// The ordinary value this channel carries in the fixture when it is not the one
        /// being poisoned — deliberately all different, so a mix-up cannot pass.
        var goodValue: Float {
            switch self {
            case .bpm: return 70
            case .coherence: return 0.5
            case .hrv: return 0.4
            case .breath: return 6
            }
        }

        func read(_ peek: BioPeek) -> Float {
            switch self {
            case .bpm: return peek.bpm
            case .coherence: return peek.coherence
            case .hrv: return peek.hrvNormalized
            case .breath: return peek.breathRate
            }
        }
    }

    private func frame(source: BioSource, channel: Channel, value: Float) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1000,
                       heartRateBPM: channel == .bpm ? value : Channel.bpm.goodValue,
                       hrvNormalized: channel == .hrv ? value : Channel.hrv.goodValue,
                       breathRate: channel == .breath ? value : Channel.breath.goodValue,
                       breathPhase: 0.5,
                       coherence: channel == .coherence ? value : Channel.coherence.goodValue,
                       motionEnergy: 0,
                       source: source)
    }

    // MARK: - Source access (house template)

    private struct WritableAnchorMissing: Error { let reason: String }

    /// Directory-gated, never per-file (#475): a `fileExists` bracket around each read turns
    /// the very catastrophe this file guards against into a green SKIP.
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw WritableAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or \
                moved. Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
