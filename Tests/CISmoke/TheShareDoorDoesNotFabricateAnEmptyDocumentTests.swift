// TheShareDoorDoesNotFabricateAnEmptyDocumentTests.swift
// Echoel — CISmoke (the BLOCKING bundle). Guard for #519.
//
//  ⚠️ THE LIMIT FIRST, because half of this file is a source scan. `Project` is `public`,
//  pure `Codable` and Foundation-only, so the ENCODER half below drives shipped code end to
//  end — it really encodes, really throws, and really reads the bytes back. The WIRING half —
//  that `SharedEchoelProject` asks that encoder and that `ProjectStore` stopped printing its
//  own — is a scan over the source text: the wrapper is `internal`, `@available(iOS 16.0, *)`,
//  and `DataRepresentation`'s closure is not reachable from a test bundle. **That the share
//  sheet now REPORTS a failed export instead of delivering a file is a DEVICE trial and is
//  OPEN.**
//
//  ⭐ WHAT THIS IS ABOUT, and it is worse than the silence #518 closed one door over. The
//  `ShareLink` wrapper ended in `(try? JSONEncoder().encode(shared.project)) ?? Data()`. A
//  `DataRepresentation` closure that RETURNS empty bytes has not failed: the share sheet
//  completes, a 0-byte file goes out carrying the take's real name (`<name>.echoel.json`),
//  and the sender is told nothing. The failure surfaces on SOMEONE ELSE'S device, days later,
//  as `ProjectStore.importProject` returning nil — "not a valid Echoel session". **A
//  fabricated artefact that looks like success is the one outcome worse than a button that
//  visibly does nothing.** Claim 3 exists to keep that sentence a measured fact rather than a
//  rhetorical flourish: empty bytes really do fail to decode.
//
//  ⭐ AND IT WAS REACHABLE, not theoretical. `ProjectStore.save` does not validate
//  encodability — it inserts and calls `persist()`. A take carrying a non-finite value stays
//  in the in-memory library after its disk write fails (logged since #514), its row renders
//  like any other, and its share button is what then produces the empty file.
//  `JSONEncoder`'s default `nonConformingFloatEncodingStrategy` is `.throw`, and this type
//  carries `bpm`, `a4Hz`, a whole `SynthPatch`, every `Note` and (since #217) a whole
//  `RawTake` through exactly this encoder.
//
//  ⭐ THE SECOND HALF IS #416 AT ITS QUIETEST: "encode a Project for sharing" was decided
//  TWICE and the two answers disagreed on BOTH halves. FORMAT — `ProjectStore.exportData`
//  set `.prettyPrinted` + `.sortedKeys` and called the result "human-diffable"; the wrapper
//  used a bare `JSONEncoder()`, so the SHIPPED export was minified with unstable key order.
//  The promise was made in the method nobody calls (zero production callers, measured) and
//  broken in the one everybody reaches. FAILURE — one returned `nil`, the other `Data()`.
//
//  ⚠️ HONEST GRADING (#433), and the first pass of this paragraph was wrong in the
//  FLATTERING direction — it counted five regressions. Transcribed rather than asserted.
//   · The file CANNOT BE GRADED AT ALL against the parent — claims 1 and 2 name
//     `sharedDocumentData()`, which does not exist there, so the bundle does not compile and
//     NO claim has a verdict (#464, said plainly rather than dressed up). Hand-transcribed
//     against `git show HEAD:` with a Python rebuild of `SourceText.codeOnly` and the brace
//     matcher instead.
//   · RED on the parent for their NAMED reason, anchors PRESENT on both trees: the three
//     needles of claim 4 and the first two of claim 5. Those five needles are **TWO findings**,
//     not five (#486): claim 4's three are the positive and the two negative sides of ONE
//     substitution inside ONE declaration; claim 5's two are one finding on the store.
//   · FORWARD GUARDS that could never have been red, because they drive a symbol THIS commit
//     creates: claims 1 and 2. Booking them as regressions would be the #433 defect in the
//     flattering direction — and claim 2 especially, because the parent's `exportData`
//     already produced pretty+sorted. The format was never wrong where it was written; it was
//     wrong where it was used.
//   · GREEN ON BOTH TREES, i.e. COUNTERWEIGHTS: claims 3, 5's third needle, 6 and 7. They
//     carry the weight, because each fails an obvious later "cleanup": treat empty bytes as an
//     acceptable export; make `exportData` throw "for symmetry"; pretty-print the App Group
//     library on every autosave; pretty-print the colab wire payload on `.unreliable`.
//
//  ⚠️ `SourceText.codeOnly` IS LOAD-BEARING HERE, and that is MEASURED rather than assumed
//  (#484/#485 each had to withdraw the stronger claim once, #486 twice): raw vs stripped
//  differ on **1 of 22** needle verdicts across both trees — the zero-encoder count, because the ⛔
//  retraction this slice writes into `ProjectStore` quotes `JSONEncoder()` verbatim to explain
//  why there must not be one. A raw-text scan would be RED ON CORRECT CODE. The #486/#491
//  collision again: this repo writes down what it removed, so a counting scan meets its own
//  obituary.

import XCTest
@testable import Echoelmusic

final class TheShareDoorDoesNotFabricateAnEmptyDocumentTests: XCTestCase {

    private static let view = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let store = "Sources/Echoelmusic/Core/ProjectStore.swift"
    private static let project = "Sources/Echoelmusic/Core/Project.swift"
    private static let group = "Sources/Echoelmusic/Core/AppGroupStore.swift"
    private static let payload = "Sources/Echoelmusic/Sync/ColabPayload.swift"

    // MARK: - fixture

    private func take(bpm: Double = 124) -> Project {
        Project(
            name: "Take", styleRaw: "dubTechno", keyRoot: 0, scaleRaw: "minor", bpm: bpm,
            modeRaw: "studioLocked", fxCharacterRaw: "auto", loopBars: 2, a4Hz: 440,
            toneSystemID: "edo12", moodFields: nil, artist: "Echoel",
            patch: SynthPatch(name: "Default"),
            notes: [Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 0.7)],
            rawTake: nil,
            drumSteps: [], drumAccents: [])
    }

    // MARK: - 1. An unencodable take THROWS rather than becoming a file

    func testAnUnwritableTakeThrowsAndNamesTheField() throws {
        var bad = take()
        bad.bpm = .nan

        XCTAssertThrowsError(try bad.sharedDocumentData()) { error in
            guard case EncodingError.invalidValue(_, let context) = error else {
                return XCTFail("""
                    A non-finite value must surface as `EncodingError.invalidValue` — got \
                    \(error). `JSONEncoder`'s default `nonConformingFloatEncodingStrategy` is \
                    `.throw`; if this is now some other error, somebody set that strategy and \
                    a NaN is being silently substituted into a document a stranger will open.
                    """)
            }
            XCTAssertTrue(context.codingPath.contains { $0.stringValue == "bpm" }, """
                The error must NAME the field through `codingPath` (got \
                \(context.codingPath.map(\.stringValue))). That is the whole reason this form \
                throws instead of returning `Data?`: "the disk is full" and "a NaN got into \
                your piece" are different problems with different fixes, and `try?` folds both \
                onto nil (#514/#518, same lesson two doors over).
                """)
        }

    }

    // MARK: - 2. The document format is the one that was promised

    func testTheDocumentIsPrettyPrintedAndDeterministic() throws {
        let p = take()
        let data = try p.sharedDocumentData()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("\n"), """
            The shared document must be PRETTY-PRINTED. `ProjectStore.exportData` has always \
            called this "human-diffable" and set `.prettyPrinted`; the path a user actually \
            reached used a bare encoder and shipped one minified line. If this is minified \
            again, the promise moved back to the method nobody calls.
            """)

        // `.sortedKeys` is what makes "diffable" mean anything: two exports of the same take
        // must be byte-identical. Coding order starts at `schemaVersion`; sorted order starts
        // at `a4Hz` (UTF-8: "a4" < "ar" < "b" …). That difference IS the discriminator — a
        // scan for the flag would pass on a file that merely mentions it.
        let afterBrace = text.drop(while: { $0 != "\"" }).dropFirst()
        let firstKey = String(afterBrace.prefix(while: { $0 != "\"" }))
        XCTAssertEqual(firstKey, "a4Hz", """
            The first key must be `a4Hz` (sorted), not `schemaVersion` (coding order) — got \
            "\(firstKey)". Without `.sortedKeys` the byte order of a saved take depends on \
            dictionary iteration, so two exports of the SAME session diff against each other \
            and "diffable" is a word rather than a property.
            """)

        XCTAssertEqual(data, try p.sharedDocumentData(), """
            Two encodes of the same take must be byte-identical. This is the property \
            `.sortedKeys` exists for; if it fails, sharing the same session twice produces two \
            different documents.
            """)
    }

    // MARK: - 3. COUNTERWEIGHT — empty bytes are NOT a session

    func testEmptyBytesAreNotAValidSessionAndARealDocumentIs() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(Project.self, from: Data()), """
            Empty bytes must FAIL to decode. This is what makes the old `?? Data()` a defect \
            rather than an untidiness: the share sheet completed, a named file went out, and \
            the recipient got "not a valid Echoel session" days later. If empty data ever \
            starts decoding into a default `Project`, fabricating one becomes plausible again.
            """)

        let restored = try JSONDecoder().decode(Project.self, from: try take().sharedDocumentData())
        XCTAssertEqual(restored.name, "Take", """
            A real document must still round-trip. Without this the assertion above is green \
            about nothing — a `Project` that decodes from NOTHING would satisfy it too (#343).
            """)
        XCTAssertEqual(restored.bpm, 124, accuracy: 0.0001)
    }

    // MARK: - 4. The share door asks the document form and fabricates nothing

    func testTheShareLinkWrapperUsesTheDocumentFormAndNeverFabricatesBytes() throws {
        let body = try declarationBody(of: "struct SharedEchoelProject: Transferable {",
                                       in: Self.view)

        XCTAssertTrue(body.contains("try shared.project.sharedDocumentData()"), """
            The `ShareLink` wrapper must encode through the document form. \
            `DataRepresentation`'s exporting closure is `async throws`, so letting it throw \
            was always available — the system then reports a failed export instead of \
            delivering a corrupt file.
            """)
        XCTAssertFalse(body.contains("JSONEncoder("), """
            The wrapper is printing its own encoder again. That is exactly how the format \
            split: the "human-diffable" promise lived in `ProjectStore.exportData` and the \
            shipped bytes came from here, minified and unsorted (#416).
            """)
        XCTAssertFalse(body.contains("?? Data()"), """
            `?? Data()` is back. Empty bytes are not an error — the closure RETURNS, the share \
            sheet completes, and a 0-byte file goes out under the take's real name. This is \
            the #519 defect verbatim, and it is worse than the silent tap #518 closed.
            """)
    }

    // MARK: - 5. …and the store no longer decides the format either

    func testTheStoreDelegatesAndConstructsNoEncoderOfItsOwn() throws {
        let body = try declarationBody(of: "public func exportData(_ project: Project) -> Data? {",
                                       in: Self.store)
        XCTAssertTrue(body.contains("project.sharedDocumentData()"), """
            `exportData` must delegate to the one document form. Keeping its own encoder is \
            what let the two answers drift apart in the first place — and this method is the \
            half that nobody calls, so its drift is invisible until someone copies it.
            """)
        // COUNTERWEIGHT, green on both trees: the `Data?` contract stays. Its only callers are
        // two round-trip tests in the non-blocking suite; widening the signature in this slice
        // would touch a second surface for no behavioural gain. The tidy-looking follow-up —
        // "make this throw too, for symmetry" — is a separate decision with its own callers.
        XCTAssertTrue(body.contains("try?"), """
            `exportData` must keep answering yes/no. If it now propagates, its two callers \
            changed shape in a slice whose whole subject is the OTHER path — and the reason \
            the reachable share door throws (the field name in `EncodingError`) does not apply \
            to a caller that only asks whether bytes exist.
            """)

        let src = try code(at: Self.store)
        XCTAssertEqual(src.components(separatedBy: "JSONEncoder(").count - 1, 0, """
            `ProjectStore` must construct ZERO `JSONEncoder`s: the shared DOCUMENT belongs to \
            `Project.sharedDocumentData()` and the on-disk LIBRARY belongs to \
            `AppGroupStore.save`. A new encoder here is a third answer to "how does a Project \
            become bytes", and this file-wide count is what catches it in a method claim 5's \
            first half would never look at.
            """)
    }

    // MARK: - 6. COUNTERWEIGHT — the on-disk library is NOT this decision

    func testTheAppGroupLibraryKeepsItsOwnEncoder() throws {
        let src = try code(at: Self.group)
        XCTAssertTrue(src.contains("JSONEncoder()"), """
            `AppGroupStore` must keep its own encoder. It writes the whole `[Project]` array on \
            every autosave; pretty-printing that inflates a file nobody diffs, on the hottest \
            write path in the app.
            """)
        XCTAssertFalse(src.contains("sharedDocumentData"), """
            The library must NOT reach for the shared-document form. "One definition" is a rule \
            about ONE decision, not about one encoder for the whole app — folding these \
            together is the tidy-looking wrong answer, which is why it gets an assertion rather \
            than a comment.
            """)
    }

    // MARK: - 7. COUNTERWEIGHT — the colab wire payload is NOT this decision either

    func testTheColabWirePayloadKeepsItsOwnFormat() throws {
        let src = try code(at: Self.payload)
        XCTAssertFalse(src.contains("sharedDocumentData"), """
            `ColabPayload` carries a `Project` over Multipeer on an `.unreliable` transport. \
            Pretty-printing it spends bandwidth on whitespace nobody reads, and #512 pinned its \
            own non-finite policy separately. (How many encoders IT constructs is #518's claim \
            7 — not repeated here, because a second weaker copy of a live assertion is the very \
            duplication this slice removes.)
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
