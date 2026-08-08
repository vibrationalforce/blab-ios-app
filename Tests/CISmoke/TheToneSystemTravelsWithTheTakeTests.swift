// TheToneSystemTravelsWithTheTakeTests.swift
// Echoel — #493. A take carried ONE of its two tuning axes. `a4Hz` (the Kammerton) has been
// written into `Project` and restored by `open(_:)` since this format existed; the TONE SYSTEM
// — the cent table that makes a take Maqām Rāst rather than 12-TET — lived only in
// `@AppStorage("toneSystemID")`, i.e. in the instrument, never in the file. So: play a Rāst
// loop, save it, switch the instrument to 12-TET, reopen the loop → 12-TET. `open(_:)` even
// ends in `applyTuning()`, which faithfully pushes the GLOBAL table to every voice.
//
// ⭐ THIS IS #312/#338 ARRIVING BY A DIFFERENT ROAD. Those two closed the same "two tunings at
// once" hole INSIDE one session (the sub-bass, then `bioVoice` + `LaneVoiceRack`). #338 shipped
// in v10.79.374 and its own deploy note asks the founder to try Maqām and then A4 — so he is
// about to meet exactly the asymmetry this slice removes: one of those two knobs sticks to a
// saved take and the other does not.
//
// ⚠️ WHAT IS ACTUALLY PINNED HERE, said before anything else. `Project` is `public` and pure
// `Codable`, so the PERSISTENCE half is real behaviour driven end to end — encode, decode,
// legacy bytes, absent key. The WIRING half (does `currentProject()` write it, does `open(_:)`
// read it) is a SOURCE SCAN, because both live in `private` members of a view no test in this
// bundle can instantiate. Nothing here proves a take sounds like Rāst on a device; that is a
// hearing test, and it is the same one #312 still has open.
//
// ⚠️ HONEST GRADING against the pre-#493 tree: the file cannot be graded there at all. Every
// behavioural case names `Project.toneSystemID`, which does not exist on that tree, so the
// bundle does not compile and NO assertion has a verdict (the #464 situation, said plainly
// rather than dressed up as "N regressions"). Transcribed by hand: the round-trip, the legacy
// case and the absent-key case would all be red for their stated reason; the three source scans
// would be red on their anchors; and two are COUNTERWEIGHTS that are green on both trees and
// exist to make the obvious later "cleanups" fail —
//   · giving the field a `?? "edo12"` fallback (kills the legacy case),
//   · giving the initialiser a `= nil` default (kills the no-default scan, and with it the
//     #440/#443 property that an argument no call site writes appears in no diff),
//   · making `open(_:)` assign unconditionally (kills the `if let` scan).
//
// ⚠️ `SourceText.codeOnly` is PROPHYLACTIC here, not load-bearing, and that is measured rather
// than assumed (#484/#485 both had to retract the stronger claim): raw vs stripped differ on
// **0 of 5** source-scan verdicts today — none of the three negative needles occurs in prose in
// either scanned file. It is used anyway because #453 created ONE definition of "code, not
// prose" for the whole blocking bundle, and a private exception is the defect that slice removed.
// It stops being prophylactic the moment someone writes a retraction comment that quotes
// `toneSystemID: String? = nil` verbatim — which this repo does routinely.

import Foundation
import XCTest
@testable import Echoelmusic

/// Thrown when a scan's anchor is gone: a renamed member must be a FAILURE, never a skip (#454).
private struct ToneAnchorMissing: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

final class TheToneSystemTravelsWithTheTakeTests: XCTestCase {

    // MARK: - the take itself

    /// A take that states a tone system, or none at all.
    ///
    /// `toneSystemID` is passed positionally on purpose — it has NO default on the initialiser
    /// (#440/#443), and this fixture is one of the three call sites that proves it.
    private func take(toneSystemID: String?) -> Project {
        Project(
            name: "Tone", styleRaw: MusicStyle.selfObservation.rawValue,
            keyRoot: 0, scaleRaw: Scale.major.rawValue, bpm: 72,
            modeRaw: ComposerMode.flowFree.rawValue,
            fxCharacterRaw: FXCharacter.clean.rawValue,
            loopBars: 4, a4Hz: 432, toneSystemID: toneSystemID, moodFields: nil, artist: "",
            patch: SynthPatch(name: "Test"), notes: [], rawTake: nil,
            drumSteps: [], drumAccents: [])
    }

    /// `maqam-rast` and not an invented id: the stored value is `TuningSystem.named(_:)`'s key,
    /// and a fixture that used a string no library entry answers to would round-trip perfectly
    /// while proving nothing about the thing the app looks up.
    private let realNon12TET = "maqam-rast"

    // MARK: - persistence (real behaviour)

    /// THE DEFECT, in one line: a saved take must come back in the tuning it was played in.
    func testTheToneSystemSurvivesASaveAndOpen() throws {
        let data = try JSONEncoder().encode(take(toneSystemID: realNon12TET))
        let reloaded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(reloaded.toneSystemID, realNon12TET, """
            A take saved in \(realNon12TET) came back stating \
            \(reloaded.toneSystemID.map { "\"\($0)\"" } ?? "nothing"). The tone system is the \
            second tuning axis and it has to travel with the take exactly like a4Hz does — \
            otherwise reopening a Maqām loop under a 12-TET instrument silently returns 12-TET.
            """)
    }

    /// THE COUNTERWEIGHT THAT MATTERS MOST, and the reason the field is OPTIONAL.
    ///
    /// A take written before this build genuinely does not state a tone system. `nil` is the only
    /// honest reading. The tempting "tidy" change is `?? "edo12"` in the decoder — and that turns
    /// *unknown* into an *assertion*, which the open path then acts on: a player who has chosen
    /// Gamelan opens an old take and gets dragged back to 12-TET on a value that file never
    /// carried. This test is what makes that a red build instead of a shrug.
    func testALegacyTakeStatesNoToneSystemRatherThanTwelveTET() throws {
        let data = try JSONEncoder().encode(take(toneSystemID: realNon12TET))
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("Project did not encode as a JSON object — re-anchor this test.")
        }
        XCTAssertNotNil(object["toneSystemID"],
                        "The key is absent before the test even removes it — the scan below is " +
                        "measuring nothing. Check the CodingKey name.")
        object.removeValue(forKey: "toneSystemID")

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let reloaded = try JSONDecoder().decode(Project.self, from: legacy)

        XCTAssertNil(reloaded.toneSystemID, """
            A take written before #493 decoded to "\(reloaded.toneSystemID ?? "")" instead of \
            nil. Someone gave the field a default. That is not a nicety: `open(_:)` only \
            restores the tone system `if let` the take states one, so a fabricated "edo12" \
            would make opening ANY old take overwrite the player's current tuning choice.
            """)
        XCTAssertEqual(reloaded.a4Hz, 432, accuracy: 1e-9,
                       "The rest of the legacy take must still decode — if this moved too, the " +
                       "defect is in the decoder generally, not in the new field.")
    }

    /// Absent, not `null`. A take that states nothing writes NO key, so re-reading it yields
    /// `nil` again rather than a JSON null a stricter future decoder would have to special-case.
    func testANilToneSystemWritesNoKeyAndReadsBackAsNil() throws {
        let data = try JSONEncoder().encode(take(toneSystemID: nil))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(object?["toneSystemID"], """
            A take stating no tone system wrote a `toneSystemID` key anyway (probably \
            `encode` instead of `encodeIfPresent`). Round-trip stability in BOTH directions is \
            the property here: absent in → absent out.
            """)
        let reloaded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertNil(reloaded.toneSystemID, "nil did not survive its own round trip.")
    }

    /// COUNTERWEIGHT: the sibling axis. `a4Hz` travelled long before #493 and must keep doing so
    /// — a change that broke it while fixing the tone system would trade one silent tuning bug
    /// for another, and nothing else in this bundle watches the save path for it.
    func testTheOtherTuningAxisStillTravels() throws {
        let data = try JSONEncoder().encode(take(toneSystemID: realNon12TET))
        let reloaded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(reloaded.a4Hz, 432, accuracy: 1e-9,
                       "The Kammerton stopped surviving a save. Both tuning axes travel or " +
                       "neither is trustworthy.")
    }

    /// COUNTERWEIGHT: why a RAW id is stored rather than a resolved table. A take written by a
    /// build that knows a system this one does not must still load, and the lookup already falls
    /// back. Storing anything richer would make an unknown system a decode failure instead of a
    /// graceful 12-TET — i.e. would lose the whole take rather than one field (#163/#170).
    func testAnUnknownIdIsSurvivableRatherThanFatal() {
        XCTAssertEqual(TuningSystem.named(realNon12TET).id, realNon12TET,
                       "The fixture id is not a real library key — this whole file would then " +
                       "be round-tripping a string the app never looks up.")
        let unknown = TuningSystem.named("system-from-a-future-build")
        XCTAssertEqual(unknown.id, "edo12",
                       "An unknown tone-system id must fall back to 12-TET, not trap. That " +
                       "fallback is the reason it is safe to persist the raw string.")
    }

    // MARK: - wiring (source scans — see the header for what these cannot prove)

    /// The save side must write the INSTRUMENT'S current tone system, not a literal. A take this
    /// build writes always states what it was played in; `nil` is reserved for older files.
    func testTheSaveSideStatesTheInstrumentsToneSystem() throws {
        let body = try declarationBody(
            of: "private func currentProject(named name: String? = nil) -> Project {",
            in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(body.contains("toneSystemID: tuningID"), """
            `currentProject()` no longer passes the live `tuningID`. If it now passes a literal \
            or nil, every take this build writes claims the wrong tuning — and the round-trip \
            test above stays green, because the file format is fine and only the caller lies.
            """)
    }

    /// The open side must act ONLY when the take states one. The `if let` is the decision, not a
    /// nil-safety formality: for a pre-#493 take the player's current choice is the only real
    /// information in the room, and defaulting over it invents a fact about the file.
    func testTheOpenSideOnlyActsWhenTheTakeStatesOne() throws {
        let body = try declarationBody(of: "private func open(_ p: Project) {",
                                       in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(body.contains("if let savedToneSystem = p.toneSystemID"), """
            `open(_:)` no longer gates the tone-system restore on the take stating one. An \
            unconditional `tuningID = p.toneSystemID ?? "edo12"` reads like a tidy-up and \
            silently resets the instrument's tuning every time an older take is opened.
            """)
        XCTAssertFalse(body.contains("p.toneSystemID ??"), """
            `open(_:)` supplies a default for a take that states no tone system. See above: \
            that is the one behaviour this slice exists to prevent.
            """)
    }

    /// COUNTERWEIGHT: no default on the initialiser. `= nil` would keep every call site
    /// compiling untouched — which is exactly how a field ends up looking wired while every save
    /// writes nothing (#440/#443, paid for twice).
    ///
    /// ⛔ THIS SENTENCE SAID "FOUR call sites repo-wide" AND WAS WRONG WHEN WRITTEN — there are
    /// SEVEN, and the two missed ones are in `Tests/EchoelmusicTests/ProjectStoreTests.swift`,
    /// which #493 therefore shipped NOT COMPILING. Neither real gate builds that directory
    /// (#208), so nothing went red. Fixed in #494; the standing count lives on `Project.init`,
    /// which is the one place worth re-`grep`ping, not here.
    ///
    /// ⛔ I first counted TWO, having grepped the files I already had open. The missing one is
    /// `ColabPayloadTests`, in the NON-blocking suite (#208) that neither real gate compiles —
    /// so the omission could not have gone red at either gate. Counting call sites is a repo-wide
    /// grep, and the un-gated half of the tree is where an uncounted caller hides.
    func testTheInitialiserHasNoDefaultForTheToneSystem() throws {
        let text = try source("Sources/Echoelmusic/Core/Project.swift")
        XCTAssertTrue(text.contains("toneSystemID: String?,"),
                      "The initialiser no longer takes `toneSystemID` — re-anchor this scan.")
        XCTAssertFalse(text.contains("toneSystemID: String? = nil"), """
            `toneSystemID` was given a default. Then a new caller that forgets it compiles \
            cleanly and writes a take that states no tuning, and nothing in any diff shows it.
            """)
    }

    // MARK: - source access

    /// Comment-stripped source (#453 — one shared definition of "code, not prose"), a SKIP when
    /// there is no checkout, and a FAILURE when the file itself moved (#454: a skip passes CI, so
    /// "no tree" may skip and "the thing I guard was renamed" may not).
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ToneAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body following `key`, which must end in its opening brace.
    ///
    /// Brace-matched rather than "from here to the next declaration": `EchoelStudioView.swift` is
    /// ~9,900 lines and deriving scope from FILE ORDER is a mistake this repo has already paid
    /// for more than once. Braces inside string literals are not a concern for these two bodies,
    /// and pretending otherwise would mean re-implementing a lexer for no measured gain.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        guard let start = text.range(of: key) else {
            throw ToneAnchorMissing(reason: """
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
                if depth == 0 {
                    return String(text[start.upperBound..<index])
                }
            }
            index = text.index(after: index)
        }
        throw ToneAnchorMissing(reason: "Unbalanced braces after `\(key)` in \(relativePath).")
    }
}
