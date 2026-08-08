// TheImportDoorReportsWhatItCannotReadTests.swift
// Echoel — CISmoke (the BLOCKING bundle). Guard for #520.
//
//  ⚠️ THE LIMIT FIRST, because part of this file is a source scan. The SENTENCE half drives
//  shipped code end to end — `ProjectStore.importFailureNote` is `nonisolated public static`
//  and Foundation-only, the errors it maps come from real decodes, and the string under test
//  is the string the sheet renders. The STORE half (claim 9) drives it further still: a real
//  `ProjectStore` over its own container subdirectory really imports a real document and
//  really refuses a bad one. The WIRING half — that the `.fileImporter` handler switches on
//  the result, catches, and sets the note — is a scan over the source text, because
//  `importNote` is `@State` on a view no test bundle can instantiate. **That a failed import
//  now SAYS SO on the device is a DEVICE trial and is OPEN.**
//
//  ⭐ WHAT THIS IS ABOUT, and it is the RECEIVING TWIN of #519. That slice's own doc block in
//  `Project.swift` describes the consequence of an empty share: it "surfaces on SOMEONE
//  ELSE'S device, days later, as `importProject` returning `nil` — 'not a valid Echoel
//  session'." Measured before writing a line of this: that sentence exists in TWO doc
//  comments and NOWHERE else. `git grep "importFailure\|importError\|showImport"` over
//  `Sources/` returned nothing, and the one production call site was
//  `if case .success(let urls) = result, let url = urls.first { projects.importProject(from:
//  url) }` — it discarded the return value AND ignored `case .failure` entirely. **The
//  receiving device said nothing at all.** Pick a file, the sheet closes, the library is
//  unchanged, and the only reading available to the user is "I must have tapped wrong".
//
//  ⭐ SO #519 AND #520 ARE ONE DEFECT SEEN FROM BOTH ENDS. #519 stopped the sender
//  fabricating a file that looks like success; this stops the receiver swallowing the
//  arrival. Either half alone leaves a user with a silent failure — and the sender's half was
//  argued FROM a message the app never printed.
//
//  ⚠️ THE NOTE NAMES THE FIELD WHERE ONE EXISTS AND INVENTS NOTHING WHERE ONE DOES NOT.
//  `.dataCorrupted` on non-JSON bytes carries an EMPTY `codingPath` — there is no field,
//  the bytes were never a document — and printing a trailing "— " with nothing after it is
//  the fabricated-detail defect this repo has paid for repeatedly (#424/#426/#433/#461).
//  Claim 1 pins the absence of that dangling separator, not merely the presence of a
//  sentence.
//
//  ⚠️ HONEST GRADING (#433), and it is the #464 situation said plainly rather than dressed
//  up: **this file cannot be graded against the parent at all.** Four of its methods name
//  `ProjectStore.importFailureNote` and a fifth names the throwing
//  `importProject(fromDocument:)`, neither of which exists there, so the bundle does not
//  compile and NO claim has a verdict. Hand-transcribed against `git show HEAD:` with a
//  Python rebuild of `SourceText.codeOnly` and the brace matcher instead:
//   · RED on the parent for their NAMED reason: the four needles of claim 5, the two of
//     claim 6, and the one of claim 7. Those seven needles are **TWO findings**, not seven
//     (#486). Finding one is that the handler ignored `.failure` and discarded the result —
//     ONE absence, reported by five needles (claim 5's four plus claim 7's, because a branch
//     that does not exist cannot suppress a cancellation either). Finding two is that nothing
//     rendered a note (claim 6's two, the positive and negative sides of one omission).
//   · FORWARD GUARDS that could never have been red, because they drive a symbol THIS commit
//     creates: claims 1–4 and 9, and claim 8's third needle (the delegation, to a throwing
//     method that did not exist). Booking those as regressions would be the #433 defect in
//     the flattering direction. Claim 9 earns its place anyway: it is the only assertion in
//     the file that proves the door's new path WORKS rather than merely that it is written,
//     and its second half pins the property that makes reporting honest — decode precedes
//     save, so a failed import is a no-op rather than an apology for a half-written row.
//   · GREEN ON BOTH TREES, i.e. the only real COUNTERWEIGHTS here: claim 8's two signature
//     needles. They carry weight because the obvious later "cleanup" is to tidy away the
//     `Project?` forms — whose only callers live in the suite no gate compiles (#208/#494),
//     so that removal is a break no CI run can show.
//
//  ⚠️ `SourceText.codeOnly` IS PROPHYLACTIC HERE, NOT LOAD-BEARING, and that is MEASURED
//  rather than assumed — #484 and #485 each had to withdraw the stronger claim once and #486
//  twice, and the first draft of THIS paragraph made it a third time, claiming "2 of 12"
//  before running the transcription. Measured: raw vs stripped differ on **0 of 10** needle
//  verdicts, on BOTH trees. The two near-collisions I expected are not collisions at all:
//  `projects.importProject(from: url)` occurs ZERO times in the raw view text (the retraction
//  quoting it lives in THIS file's header, which nothing scans), and `Couldn't read that
//  file.` appears in `ProjectStore.swift` exactly once — as a `return` statement, i.e. as
//  CODE, which is not a needle here anyway. It stays because #453 made one definition of
//  "code, not prose" for the whole blocking bundle, and it stops being prophylactic the
//  moment somebody writes a retraction in a scanned file that quotes one of these needles.

import XCTest
@testable import Echoelmusic

@MainActor
final class TheImportDoorReportsWhatItCannotReadTests: XCTestCase {

    private static let view = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let store = "Sources/Echoelmusic/Core/ProjectStore.swift"

    // MARK: - Isolated library (the `AutosaveSlotTests` pattern, and the UUID is not decoration)

    private var writtenSubdirectories: [String] = []

    /// A `ProjectStore` over its own container subdirectory. The UUID matters for the same
    /// reason it does in `AutosaveSlotTests`: a simulator container is REUSED, so a tag alone
    /// would let a second local run start from the rows the first left behind and read a
    /// library that is one import too long. CI is ephemeral per job, so this bites a developer
    /// re-running locally, never the gate.
    private func isolatedStore(_ tag: String = #function) -> ProjectStore {
        let subdirectory = "EchoelTests-import-\(tag)-\(UUID().uuidString)"
        writtenSubdirectories.append(subdirectory)
        return ProjectStore(store: AppGroupStore(subdirectory: subdirectory))
    }

    override func tearDown() async throws {
        for subdirectory in writtenSubdirectories {
            AppGroupStore(subdirectory: subdirectory).delete(name: "projects.json")
        }
        writtenSubdirectories = []
    }

    private func take(named name: String, bpm: Double = 124) -> Project {
        Project(
            name: name, styleRaw: "dubTechno", keyRoot: 0, scaleRaw: "minor", bpm: bpm,
            modeRaw: "studioLocked", fxCharacterRaw: "auto", loopBars: 2, a4Hz: 440,
            toneSystemID: "edo12", moodFields: nil, artist: "Echoel",
            patch: SynthPatch(name: "Default"),
            notes: [Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 0.7)],
            rawTake: nil,
            drumSteps: [], drumAccents: [])
    }

    // MARK: - 1. Bytes that were never a document say so, and name no field

    func testUnreadableBytesReadAsNotASessionAndNameNoField() throws {
        // A REAL decode, not a hand-built error: this is exactly what arrives when the user
        // picks a photo, a text file, or a truncated download.
        let garbage = Data("this is not json".utf8)
        var thrown: Error?
        XCTAssertThrowsError(try JSONDecoder().decode(Project.self, from: garbage)) {
            thrown = $0
        }
        let note = ProjectStore.importFailureNote(try XCTUnwrap(thrown))

        XCTAssertEqual(note, "That file isn't an Echoel session.", """
            Non-JSON bytes must read as "not a session" — got "\(note)". `.dataCorrupted` at \
            the root carries an EMPTY codingPath; there is no field to name because the bytes \
            were never a document.
            """)
        XCTAssertFalse(note.contains("—"), """
            The note ends in a dangling separator: "\(note)". Joining an empty codingPath into \
            the sentence prints "… session — " with nothing after it, which is the \
            fabricated-detail class this repo has paid for four times (#424/#426/#433/#461). \
            The emptiness of the path is information; the em dash claims there is a field.
            """)
    }

    // MARK: - 2. A real Echoel document that is wrong in ONE place names that place

    func testAMalformedFieldIsNamed() throws {
        // Also a REAL decode. `Project.init(from:)` is `decodeIfPresent` on every key, so a
        // MISSING field can never throw — the reachable failure is a field of the wrong type,
        // which is what a hand-edited or foreign-tool JSON produces.
        let wrongType = Data(#"{"name":"Take","bpm":"fast"}"#.utf8)
        var thrown: Error?
        XCTAssertThrowsError(try JSONDecoder().decode(Project.self, from: wrongType)) {
            thrown = $0
        }
        let note = ProjectStore.importFailureNote(try XCTUnwrap(thrown))

        XCTAssertTrue(note.contains("bpm"), """
            The note must NAME the offending field — got "\(note)". That is the whole reason \
            the import path throws instead of returning `Project?`: "this isn't an Echoel \
            file at all", "it is one but a field is unreadable" and "the file could not be \
            read off disk" are three problems with three different answers, and `try?` folds \
            all three onto nil (#514/#518/#519, the same lesson at three other doors). \
            ⚠️ If this reads as the empty-path sentence instead, check WHICH half moved before \
            editing the mapper: either `importFailureNote` stopped joining the path, or \
            Foundation stopped putting the key into `typeMismatch`'s `codingPath`. Only the \
            first is ours; claim 4 drives the join on a path this file controls and would stay \
            green in the second case, which is the discriminator.
            """)
        XCTAssertNotEqual(note, "That file isn't an Echoel session.", """
            A file that IS an Echoel session with one bad field must not read the same as a \
            photo. If these two collapse into one sentence, the note stops being actionable \
            and claim 1 becomes green about nothing.
            """)
    }

    // MARK: - 3. An unreachable file is NOT called an invalid session

    func testAFileSystemFailureIsNotCalledAnInvalidSession() {
        // A revoked permission, a deleted iCloud placeholder, a full disk: the DOCUMENT may
        // be perfect and simply unreadable. `Data(contentsOf:)` throws here, not the decoder.
        let note = ProjectStore.importFailureNote(CocoaError(.fileReadNoSuchFile))

        XCTAssertEqual(note, "Couldn't read that file.", """
            A non-decode failure must read as unreadable, not invalid — got "\(note)".
            """)
        XCTAssertFalse(note.lowercased().contains("session"), """
            "\(note)" calls a file that may be a perfectly good take an invalid session. That \
            sends the user to delete or re-export a document that was never the problem — the \
            same wrong-subject defect #484 removed from the acquisition cue, one door over.
            """)
    }

    // MARK: - 4. A nested field reads as a path, not as a bare leaf

    func testANestedFieldReadsAsAPath() {
        // Hand-built on purpose: the JOIN is what this claim owns, and reaching a two-element
        // codingPath through a real decode would make the assertion depend on some OTHER
        // type's decoder staying strict. This drives the mapper's own formatting.
        struct K: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
        let context = DecodingError.Context(
            codingPath: [K(stringValue: "patch"), K(stringValue: "filterCutoff")],
            debugDescription: "")
        let note = ProjectStore.importFailureNote(
            DecodingError.keyNotFound(K(stringValue: "filterCutoff"), context))

        XCTAssertTrue(note.contains("patch › filterCutoff"), """
            A nested path must read as a path — got "\(note)". Naming only the leaf \
            ("filterCutoff") sends the reader looking at the top level of a document where \
            the field does not appear.
            """)
    }

    // MARK: - 5. The door asks, catches, and reports

    func testTheImporterHandlerCatchesAndSetsTheNote() throws {
        let body = try declarationBody(of: "private var openSheet: some View {", in: Self.view)

        XCTAssertTrue(body.contains("switch result"), """
            The `.fileImporter` completion must switch on the whole result. The retired form \
            was `if case .success(let urls) = result` — an `if case` on ONE case, which \
            silently drops `.failure` on the floor. That is not a style preference: a \
            permission failure or a vanished iCloud file arrived there and produced nothing \
            anywhere.
            """)
        XCTAssertTrue(body.contains("try projects.importProject(fromDocument: url)"), """
            The door must use the THROWING import. The yes/no form cannot say WHY, and "why" \
            is the entire content of this slice.
            """)
        XCTAssertTrue(body.contains("importNote = ProjectStore.importFailureNote(error)"), """
            The caught error must become the note through the shared mapper. Formatting the \
            sentence at the call site would be a second definition of "what a failed import \
            says" (#416), in a view no test bundle can drive.
            """)
        XCTAssertFalse(body.contains("projects.importProject(from: url)"), """
            The discarding call is back. `@discardableResult` plus an ignored `.failure` is \
            exactly how this door went silent: every outcome — success, corrupt document, \
            unreadable file — looked identical to the user.
            """)
    }

    // MARK: - 6. …and the note actually reaches the screen

    func testTheNoteIsRenderedInTheSheet() throws {
        let body = try declarationBody(of: "private var openSheet: some View {", in: Self.view)

        XCTAssertTrue(body.contains("if let importNote"), """
            Nothing renders the note. A handler that sets state no view reads is the #343 \
            trap in its purest form — every other claim here stays green while the door is as \
            silent as it was before.
            """)
        XCTAssertTrue(body.contains("Text(importNote)"), """
            The note must be a line in the list, matching the `exportFailure` precedent \
            (#216). Not an alert: the importer this reports on is itself one of the two NESTED \
            presentation modifiers that put this file at 16, and #479 pins that as an \
            EQUALITY — a new `.alert` anywhere in the file goes red, and the black-screen law \
            (10.76.34) is why.
            """)
    }

    // MARK: - 7. Backing out is not a failure
    //
    // ⛔ NOT A COUNTERWEIGHT, though the first draft of this file labelled it one. Measured
    // against the parent: it is RED there, because the `.failure` branch did not exist at all
    // — so it is a fifth needle on finding one, not an independent green-on-both-trees pin.
    // Its VALUE is still forward (it fails the obvious later "the failure branch is three
    // lines, simplify it" cleanup); calling that a counterweight would be the #433 defect in
    // the flattering direction, on a file whose header claims to have avoided exactly that.

    func testCancellingIsNotReported() throws {
        let body = try declarationBody(of: "private var openSheet: some View {", in: Self.view)

        XCTAssertTrue(body.contains("userCancelled"), """
            The `.failure` branch must suppress a deliberate Cancel. Whether SwiftUI delivers \
            cancellation as `CocoaError.userCancelled` or simply never calls the completion \
            has varied across iOS versions and no device is available here to settle it — so \
            the check is a SUPERSET: harmless if cancellation is never delivered, essential \
            if it is. Without it, backing out of the picker puts "Couldn't read that file." on \
            screen for a user who did nothing wrong, which is the lying-control class this \
            whole family of slices removes.
            """)
    }

    // MARK: - 8. COUNTERWEIGHT — the yes/no forms stay, and the reason is not tidiness

    func testTheYesNoImportFormsStillExist() throws {
        let src = try code(at: Self.store)

        XCTAssertTrue(src.contains("public func importProject(from data: Data) -> Project?"), """
            The `Data` yes/no form is gone. Its callers live in \
            `Tests/EchoelmusicTests/ProjectStoreTests.swift` — the suite **no gate compiles** \
            (#208) — so removing or re-signing it is a break no CI run can show. #494 shipped \
            exactly that, undetected, and only surfaced when a later slice happened to grep \
            the whole repo.
            """)
        XCTAssertTrue(src.contains("public func importProject(from url: URL) -> Project?"), """
            The `URL` yes/no form is gone; same invisible-break reason as above.
            """)
        XCTAssertTrue(src.contains("try? importProject(fromDocument:"), """
            The yes/no forms must DELEGATE to the throwing ones rather than keeping a second \
            decode. Two decoders for one decision is how the export format split in #519 \
            (#416) — and here the drift would be worse, because one of the two paths is in \
            the half of the tree no gate compiles.
            """)
    }

    // MARK: - 9. The throwing import really works — and a failed one changes nothing

    func testAGoodDocumentImportsAndABadOneLeavesTheLibraryAlone() throws {
        let store = isolatedStore()
        let original = take(named: "Rāst loop")
        let document = try original.sharedDocumentData()

        let imported = try store.importProject(fromDocument: document)
        XCTAssertEqual(imported.name, "Rāst loop")
        XCTAssertEqual(imported.bpm, 124, accuracy: 0.0001)
        XCTAssertNotEqual(imported.id, original.id, """
            An import must get a FRESH id. Without it, importing your own export overwrites \
            the original by `id` in `ProjectStore.save` — the one way this door can destroy a \
            take rather than add one.
            """)
        XCTAssertEqual(store.projects.count, 1)

        // The safety property the throwing form must not cost: a failed import is a NO-OP.
        // `importProject` decodes BEFORE it saves, so a document that cannot become a take
        // cannot half-write one either — and that ordering is what makes reporting the error
        // an honest thing to do rather than an apology for a mess already made.
        XCTAssertThrowsError(try store.importProject(fromDocument: Data("nope".utf8)))
        XCTAssertEqual(store.projects.count, 1, """
            A failed import changed the library. Decode must precede `save`; if it does not, \
            the note this slice adds would be reporting a failure that already left a \
            half-written row behind.
            """)
        XCTAssertEqual(store.projects.first?.name, "Rāst loop")
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
