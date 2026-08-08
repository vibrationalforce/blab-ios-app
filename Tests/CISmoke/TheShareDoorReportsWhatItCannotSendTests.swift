// TheShareDoorReportsWhatItCannotSendTests.swift
// Echoel — CISmoke (the BLOCKING bundle). Guard for #518.
//
//  ⚠️ THE LIMIT FIRST, because half of this file is a source scan. `MultipeerSession` lives
//  behind `#if canImport(MultipeerConnectivity)`, `share(project:)` writes a `private(set)`
//  property on a `@MainActor` class, and driving it needs a real MC stack and a second
//  device. So the ENCODER half below is real behaviour driven end to end through the shipped
//  `public` type; the WIRING half — that `share(project:)` actually asks the throwing form and
//  actually reports — is a scan over the source text. **That a second phone sees the status
//  line, and that the sentence reads right to a person mid-performance, is a TWO-DEVICE trial
//  and is OPEN.**
//
//  ⭐ WHAT THIS IS ABOUT. `share(project:)` had THREE exits and only TWO of them said
//  anything: `status = "No peers connected"`, `status = "Share failed"`, and a bare `return`
//  when `payload.encoded()` — a `try?` — handed back `nil`. The user taps "Share current
//  session" and the button visibly does nothing, on the one surface where the status line is
//  the whole feedback channel.
//
//  ⭐ THE SILENT EXIT IS THE ONLY ONE AN ORDINARY TAP CAN REACH, which is what makes this a
//  defect rather than an untidiness. `LiveColaboView.shareButton` is
//  `.disabled(colab.connectedPeerNames.isEmpty)`, so the peers branch is pre-empted by the UI
//  except in a race (our mirrored name list and `mcSession.connectedPeers` are two different
//  sources). The transport branch needs `mcSession.send` itself to throw. The encode branch
//  needs only a NaN — and `JSONEncoder`'s default `nonConformingFloatEncodingStrategy` is
//  `.throw`, while `Project` carries `bpm`, `a4Hz`, a whole `SynthPatch`, every `Note` and
//  (since #217) a whole `RawTake` through exactly this encoder.
//
//  ⭐ ONE DEFECT, THREE DOORS, TWO ALREADY FIXED. #514 gave the SAVE path a voice for this
//  exact failure on this exact `Project`. #512 closed it for `BioPeek` on the bio stream, by
//  making the value writable at construction. The SHARE path was the one left mute.
//
//  ⚠️ SILENCE STAYS CORRECT ON THE BIO STREAM, and claim 5 is here to keep it. `sendBio` runs
//  at `PeerReading.sendInterval` over an `.unreliable` transport: a lost telemetry frame is
//  worthless a moment later, and one log line per drop would flood. The tidy-looking follow-up
//  — "make both paths report" — is the wrong direction, so it gets an assertion rather than a
//  comment.
//
//  ⚠️ HONEST GRADING (#433), and the first draft of this paragraph was wrong in the
//  FLATTERING direction on two of its six claims — caught by transcribing rather than
//  asserting, before the commit.
//   · Claim 1 CANNOT BE GRADED AT ALL against the parent — it names `encodedThrowing()`,
//     which does not exist there, so the bundle does not compile and NO claim has a verdict
//     (#464, said plainly rather than dressed up). Hand-transcribed against `git show HEAD:`
//     with a Python rebuild of `SourceText.codeOnly` and the brace matcher instead.
//   · RED on the parent for their NAMED reason, with the anchor PRESENT on both trees:
//     **3a, 3b, 4a, 4b, 6b**. Those five needles are THREE findings, not five (#486):
//     3a+3b are the two sides of ONE substitution (`encoded()` → `encodedThrowing()`);
//     4a+6b are one finding on the SCREEN (a status is written at all / it does not borrow
//     the transport's wording); 4b is a separate one on the LOG. Screen and log are not the
//     same artifact and do not fail together — #514 shipped the log half alone.
//   · GREEN ON BOTH TREES, i.e. COUNTERWEIGHTS rather than regressions: **2, 5, 6a and 7**.
//     They carry the weight of the file, because each one fails an obvious later "cleanup":
//     change the wire format while adding the throwing form; make the bio stream loud too;
//     collapse both failures onto one sentence; hand the share path its own encoder.
//   · ⛔ Claim 4 sat in the RED list on a FALSE basis until it was measured, and the first
//     draft of this very paragraph asserted it. Its first anchor was the first `} catch {` —
//     which on the parent is the TRANSPORT catch, and that has always written `status`. It
//     was GREEN on the broken code, and would have stayed green after a revert. Re-anchored
//     on a window bounded by two lines that exist on both trees; the ⛔ note at the assertion
//     keeps the trap from being re-introduced. Claim 7 was in the same list and is genuinely
//     a counterweight: the parent already constructs exactly one encoder.
//
//  ⚠️ `SourceText.codeOnly` IS LOAD-BEARING HERE, and that is MEASURED rather than assumed
//  (#484/#485 each had to withdraw the stronger claim once, #486 twice): `JSONEncoder()`
//  occurs **2×** raw / **1×** in code on the parent and **3×** raw / **1×** in code here —
//  the extra raw hits are the very comments explaining why there must be only one. Claim 7
//  would be RED ON CORRECT CODE on BOTH trees without the stripper. The #486/#491 collision
//  again: this repo writes down what it does, so a counting scan meets its own rationale.

import XCTest
@testable import Echoelmusic

final class TheShareDoorReportsWhatItCannotSendTests: XCTestCase {

    private static let session = "Sources/Echoelmusic/Sync/MultipeerSession.swift"
    private static let payload = "Sources/Echoelmusic/Sync/ColabPayload.swift"

    // MARK: - 1. The error survives the throwing form; `encoded()` still answers yes/no

    func testTheThrowingFormKeepsTheErrorAndTheOptionalFormStillHidesIt() throws {
        // `BioPeek`'s stored properties are `public var`, so a value can be made unwritable
        // AFTER the sanitising init — which is exactly the hole #512's own note describes.
        var peek = BioPeek(bpm: 60, coherence: 0.5, hrvNormalized: 0.5, breathRate: 6)
        peek.bpm = .nan
        let bad = ColabPayload(kind: "bio", senderName: "me", bio: peek)

        XCTAssertNil(bad.encoded(), """
            `encoded()` must still be the yes/no form — it is what `sendBio` relies on, and a \
            non-finite value must still be a FAILURE rather than a silently substituted number. \
            If this now returns Data, someone set `nonConformingFloatEncodingStrategy`, and the \
            share door has nothing left to report (#512 pins the absence of that setting).
            """)

        XCTAssertThrowsError(try bad.encodedThrowing(), """
            The throwing form must let the encoder's error out. Its whole reason to exist is \
            that `EncodingError.codingPath` NAMES THE FIELD that could not be written — which \
            is the substantive half of #514, on the same class of payload.
            """)
    }

    // MARK: - 2. COUNTERWEIGHT — the wire format is unchanged

    func testTheTwoFormsProduceTheSameBytesForAWritableValue() throws {
        let peek = BioPeek(bpm: 61.5, coherence: 0.25, hrvNormalized: 0.75, breathRate: 5.5)
        let good = ColabPayload(kind: "bio", senderName: "me", bio: peek)

        let viaOptional = try XCTUnwrap(good.encoded())
        let viaThrowing = try good.encodedThrowing()

        XCTAssertEqual(viaOptional, viaThrowing, """
            Adding the throwing form must not change a single byte on the wire. If these \
            diverge, someone gave one path an `outputFormatting` or a date strategy the other \
            does not have — which is the two-definitions failure (#416) that claim 7 exists to \
            prevent, arriving through the back door instead.
            """)
    }

    // MARK: - 3. The share door asks the form that keeps the error

    func testShareUsesTheThrowingFormAndNoLongerSwallowsTheFailure() throws {
        let body = try declarationBody(of: "public func share(project: Project) {",
                                       in: Self.session)
        XCTAssertTrue(body.contains("try payload.encodedThrowing()"), """
            `share(project:)` must encode through the throwing form. Without it there is no \
            error to log and no way to tell "the disk of a peer refused" from "a NaN is in \
            your song" — the distinction #514 kept for exactly this reason.
            """)
        XCTAssertFalse(body.contains("payload.encoded()"), """
            The `try?` form is back on the share path, so the encoder's error is being thrown \
            away again. That is the #518 defect verbatim: a tap that does nothing and says \
            nothing. `encoded()` is correct for `sendBio` (claim 5) and wrong here.
            """)
    }

    // MARK: - 4. …and says so, on the screen AND in the log

    func testTheEncodeFailureWritesTheStatusAndLeavesATrace() throws {
        let body = try declarationBody(of: "public func share(project: Project) {",
                                       in: Self.session)
        // ⛔ THE WINDOW IS BUILT FROM THE PAYLOAD TO THE PEERS LOOKUP, and NOT from the first
        // `} catch {`. That was the first version, and MEASURING it against the parent tree
        // showed it GREEN on the broken code: with no encode `catch` there, the first one in
        // the method is the TRANSPORT catch, which has always written `status`. A scan that
        // cannot fail for its named reason is the #367 trap, and it would have gone on
        // passing after someone restored the bare `return`. These two anchors exist on BOTH
        // trees, so this fails for the reason it states rather than for an absent anchor
        // (#486).
        guard let open = body.range(of: "let payload = ColabPayload(kind: \"session\""),
              let close = body.range(of: "let peers = mcSession.connectedPeers") else {
            throw AnchorMissing(reason: """
                `share(project:)` no longer opens with the session payload and then reads \
                `mcSession.connectedPeers`. This window is anchored on both; re-anchor it \
                rather than deleting the assertion (#454).
                """)
        }
        let encodeFailure = String(body[open.upperBound..<close.lowerBound])

        XCTAssertTrue(encodeFailure.contains("status ="), """
            The encode failure must write `status`. This method already reports on its two \
            other exits and `LiveColaboView` already renders that line — the surface EXISTS, \
            so a silent `return` here is not a missing feature, it is an unused surface.
            """)
        XCTAssertTrue(encodeFailure.contains("log.log(.error"), """
            The encode failure must also leave a trace at error level. The status line is \
            transient and the next status write erases it; the log is the telemetry FLOOR that \
            survives to a sysdiagnose, exactly as #514 established for the save path.
            """)
    }

    // MARK: - 5. COUNTERWEIGHT — the bio stream stays deliberately silent

    func testTheBioStreamKeepsTheQuietForm() throws {
        let body = try declarationBody(of: "public func sendBio(_ frame: BioSampleFrame) {",
                                       in: Self.session)
        XCTAssertTrue(body.contains("payload.encoded()"), """
            `sendBio` must KEEP the `try?` form. It runs at `PeerReading.sendInterval` over an \
            unreliable transport, where a dropped frame is worthless a moment later and one log \
            line per drop would flood the very log #518 is trying to make readable. Making both \
            paths loud is the tidy-looking wrong answer; the two paths differ in KIND.
            """)
    }

    // MARK: - 6. COUNTERWEIGHT — the sentence must not read as "try again"

    func testTheEncodeFailureDoesNotBorrowTheTransportWording() throws {
        let body = try declarationBody(of: "public func share(project: Project) {",
                                       in: Self.session)
        XCTAssertTrue(body.contains("\"Share failed\""), """
            The TRANSPORT failure keeps its own wording — that one IS worth retrying (a peer \
            dropped, the link glitched). This assertion is here so the fix for #518 cannot be \
            "make them both say the same thing".
            """)
        XCTAssertTrue(body.contains("can't be encoded"), """
            The ENCODE failure needs its own sentence, and it must name the SESSION rather than \
            the network: re-tapping re-encodes the same project and fails identically, so \
            wording that invites a retry sends the user into a loop. It must also NOT point at \
            "Diagnostics" — `log.log` goes to os_log, NOT to `EchoelCrashLog.currentLog()`, \
            which is what that row renders (the overclaim #484 had to withdraw).
            """)
    }

    // MARK: - 7. COUNTERWEIGHT — one definition of "how a payload becomes bytes"

    func testThePayloadConstructsExactlyOneEncoder() throws {
        let src = try code(at: Self.payload)
        let encoders = src.components(separatedBy: "JSONEncoder()").count - 1
        XCTAssertEqual(encoders, 1, """
            `ColabPayload` must construct exactly ONE `JSONEncoder` (found \(encoders)). \
            `encoded()` is the throwing form behind a `try?`, so there is a single answer to \
            "how does a payload become bytes". A second construction is a second place for a \
            future `outputFormatting` or date strategy to be set on one wire path and not the \
            other (#416) — and claim 2 would only catch that AFTER it had already shipped a \
            divergence.
            """)
    }

    // MARK: - Source access (house template)

    private struct AnchorMissing: Error { let reason: String }

    /// Directory-gated, never per-file (#475): a `fileExists` bracket around each read turns the
    /// very catastrophe this file guards against into a green SKIP.
    private func code(at relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body following `key`, which must end in its opening brace.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try code(at: relativePath)
        guard let start = text.range(of: key) else {
            throw AnchorMissing(reason: """
                \(relativePath) no longer declares `\(key)`. This scan is anchored on it; \
                re-anchor rather than deleting the assertion.
                """)
        }
        var depth = 0
        var index = text.index(before: start.upperBound)   // the opening brace itself
        while index < text.endIndex {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" {
                depth -= 1
                if depth == 0 { return String(text[start.upperBound..<index]) }
            }
            index = text.index(after: index)
        }
        throw AnchorMissing(reason: "Unbalanced braces after `\(key)` in \(relativePath).")
    }
}
