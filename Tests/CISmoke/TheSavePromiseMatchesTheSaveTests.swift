// TheSavePromiseMatchesTheSaveTests.swift
// Echoel — #495. The Save door's message read "Saves the current sound, key, tempo and generated
// loop." That sentence was true when it was written and has been quietly wrong ever since:
// `Project` gained `a4Hz`, then `toneSystemID` (#493), then a restore for `modeRaw` (#494), and
// the copy never moved. So the app was saving MORE than it admitted, on the one surface whose
// entire job is telling the user what a save IS — a player in Maqām Rāst at A=442 had no way to
// know that came back with the take.
//
// ⭐ UNDER-CLAIMING IS THE FRIENDLY DIRECTION AND IT IS STILL A FALSE DESCRIPTION, which is the
// only reason this is a slice at all. Nothing was broken; nothing sounded wrong. What was wrong
// is that the sentence could not be used to decide anything — and a user deciding "can I switch
// the instrument to 12-TET and get my Rāst loop back" is exactly who reads it. This repo has paid
// for the opposite direction repeatedly (#435's caption promising silence, #480's VoiceOver hint
// promising sliders, #491's box promising a pulse); the same law cuts both ways.
//
// ⚠️ WHAT IS ACTUALLY PINNED HERE, said before anything else. The COPY half is a SOURCE SCAN —
// the alert lives in a `private` member of a view no test in this bundle can instantiate, so
// nothing here proves the sentence RENDERS, that it fits the alert on a 360-pt phone, or that
// VoiceOver reads it well. Those are device checks and all three are open. The half that IS real
// behaviour is the wire: `Project` is `public` and pure `Codable`, so "everything the promise
// names is genuinely on the take" and "the two named omissions really are absent" are driven end
// to end through the shipped encoder.
//
// ⭐ THE COUNTERWEIGHTS ARE THE POINT, and they are the #343 shape: a guard that only asserts
// the new wording stays green on a tree that kept the sentence and LOST the capability — copy
// outliving the thing it describes is a worse failure than copy lagging it, because the words
// still sound authoritative. So the wire assertions and the `currentProject()` scan are
// deliberately complementary: encoding proves `Project` CAN carry each field, the scan proves
// the save door actually FILLS it. Either alone is satisfiable by a take that states nothing.
//
// ⚠️ HONEST GRADING against the pre-#495 tree, transcribed rather than claimed. THREE cases are
// regressions and all three are the copy — and two of those (`…NamesWhatTravels` and
// `…NoLongerUnderclaims`) are the positive and negative halves of ONE replacement, said plainly
// rather than counted as two findings (#433). The remaining FOUR are green on both trees and are
// counterweights against the obvious later cleanups: shortening the sentence back, dropping the
// omissions clause as "noise", or adding a mixer field to `Project` without touching the copy.
//
// ⚠️ `SourceText.codeOnly` is PROPHYLACTIC here, and that is MEASURED rather than assumed (#484
// and #485 each had to retract the stronger claim, and #486 had to retract it twice): raw vs
// stripped differ on **0 of 5** needle verdicts on this file. It stays because #453 made one
// definition of "code, not prose" for the whole blocking bundle and a private exception is
// exactly the defect that slice removed — and it stops being prophylactic the moment someone
// writes a retraction here quoting the old sentence verbatim, which is how #486 and #491 both
// ended up load-bearing.

import XCTest
@testable import Echoelmusic

final class TheSavePromiseMatchesTheSaveTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - the promise (source scans)

    /// THE REGRESSION. The message must name every axis the save actually carries. `tuning` is
    /// one word for two fields (`a4Hz` and `toneSystemID`) on purpose — the user has one mental
    /// object there, and the wire case below is what keeps that shorthand honest.
    func testTheSaveMessageNamesWhatTravels() throws {
        let message = try saveAlertMessage()
        XCTAssertFalse(message.isEmpty, "empty message closure — the anchor matched nothing (#367)")
        XCTAssertTrue(message.contains("genre, key, tuning, tempo, Flow/Loop mode"),
                      "the Save door is the one place that says what a save is; it must name the "
                      + "tuning and the Flow/Loop mode, both of which travel since #493/#494")
    }

    /// THE SECOND REGRESSION. Naming what does NOT travel is the half that prevents the far worse
    /// discovery — reopening a take and finding it mixed differently.
    func testTheSaveMessageNamesWhatDoesNot() throws {
        let message = try saveAlertMessage()
        XCTAssertFalse(message.isEmpty, "empty message closure — the anchor matched nothing (#367)")
        XCTAssertTrue(message.contains("stay with the instrument"),
                      "a promise that lists only what it keeps invites the user to assume it "
                      + "keeps everything")
    }

    /// THE THIRD REGRESSION, and the same edit seen from the other side: the short sentence must
    /// not come back alongside the long one. Its value is not the removal (case one covers that)
    /// but the DUPLICATION — two descriptions of one save, disagreeing.
    func testTheSaveMessageNoLongerUnderclaims() throws {
        let message = try saveAlertMessage()
        XCTAssertFalse(message.isEmpty, "empty message closure — the anchor matched nothing (#367)")
        XCTAssertFalse(message.contains("the current sound, key, tempo and generated loop"),
                       "this sentence predates `a4Hz`, `toneSystemID` and the mode restore — it "
                       + "describes a save the app stopped performing")
    }

    /// COUNTERWEIGHT, and the #343 trap in its exact shape. The wire case below proves `Project`
    /// CAN carry the tuning and the mode; only this proves the Save door FILLS them. Without it,
    /// a tree where `currentProject()` passed `toneSystemID: nil` keeps every other assertion
    /// green while the sentence promises something no saved file contains.
    func testTheSaveDoorActuallyFillsWhatThePromiseNames() throws {
        let body = try declarationBody(
            of: "private func currentProject(named name: String? = nil) -> Project {",
            in: Self.studio)
        XCTAssertFalse(body.isEmpty, "empty body — the anchor matched nothing useful (#367)")
        for (field, needle) in [
            ("tuning (tone system)", "toneSystemID: tuningID"),
            ("tuning (concert pitch)", "a4Hz: session.a4Hz"),
            ("Flow/Loop mode", "modeRaw: ComposerMode(locked: lockBPM).rawValue"),
            ("sound", "patch: currentPatch"),
            ("FX character", "fxCharacterRaw: fxCharacter.rawValue"),
            ("the loop", "notes: pianoRoll.notes")
        ] {
            XCTAssertTrue(body.contains(needle),
                          "the message names \(field), so the save must record it — `\(needle)`")
        }
    }

    // MARK: - the wire (real behaviour)

    private func take() -> Project {
        Project(
            name: "Rāst loop", styleRaw: "dubTechno", keyRoot: 2, scaleRaw: "minor", bpm: 96,
            modeRaw: ComposerMode.studioLocked.rawValue, fxCharacterRaw: "auto", loopBars: 8,
            a4Hz: 442, toneSystemID: "maqam-rast", artist: "Echoel",
            patch: SynthPatch(name: "Default"),
            notes: [Note(pitch: 62, startStep: 0, lengthSteps: 4, velocity: 0.6)],
            drumSteps: [], drumAccents: []
        )
    }

    private func encodedKeys(of project: Project) throws -> Set<String> {
        let data = try JSONEncoder().encode(project)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   "Project must encode as a JSON object")
        return Set(object.keys)
    }

    /// COUNTERWEIGHT on the wire. Every axis the sentence names must be a key a saved take
    /// actually writes — driven through the shipped encoder, not read off the struct. This is
    /// what stops the copy from outliving the capability if a later slice drops a field.
    func testEverythingThePromiseNamesIsOnTheWire() throws {
        let keys = try encodedKeys(of: take())
        for (word, key) in [
            ("genre", "styleRaw"), ("key", "keyRoot"), ("key", "scaleRaw"),
            ("tuning", "a4Hz"), ("tuning", "toneSystemID"), ("tempo", "bpm"),
            ("Flow/Loop mode", "modeRaw"), ("sound", "patch"),
            ("FX character", "fxCharacterRaw"), ("the loop", "notes")
        ] {
            XCTAssertTrue(keys.contains(key),
                          "the Save message says \"\(word)\" travels, so `\(key)` must be saved")
        }
    }

    /// COUNTERWEIGHT on the second sentence. The mixer is a CONSOLE setting: `MixerStore`
    /// persists each role straight into `UserDefaults`, and no `Project` CodingKey touches it.
    /// If a later slice adds one, this goes red — which is correct, because at that moment the
    /// sentence "your mixer levels stay with the instrument" becomes a lie.
    func testTheNamedOmissionsAreReallyAbsentFromTheTake() throws {
        let keys = try encodedKeys(of: take())
        for key in keys {
            XCTAssertFalse(key.lowercased().contains("mix"),
                           "`\(key)` looks like a mixer field on a saved take, but the Save "
                           + "message tells the user mixer levels stay with the instrument")
        }
        for storageKey in MixerStore.storageKeys {
            XCTAssertFalse(keys.contains(storageKey),
                           "`\(storageKey)` is a `UserDefaults` console key; a take must not "
                           + "carry it while the Save message says it does not")
        }
    }

    /// COUNTERWEIGHT on the FX half of the second sentence. Only the CHARACTER travels — the
    /// chains themselves are rebuilt from it on open. A later slice that persisted a full FX
    /// preset per take would make "hand-dialled FX stay with the instrument" false, and this is
    /// the assertion that would notice.
    func testOnlyTheFXCharacterTravelsNotTheChains() throws {
        let keys = try encodedKeys(of: take())
        XCTAssertTrue(keys.contains("fxCharacterRaw"),
                      "the character is the one FX fact a take records")
        for key in keys where key != "fxCharacterRaw" {
            XCTAssertFalse(key.lowercased().hasPrefix("fx"),
                           "`\(key)` is a second FX field on the take; the Save message promises "
                           + "only the character travels")
        }
    }

    // MARK: - source access

    private struct SaveAnchorMissing: Error { let reason: String }

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
            throw SaveAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The SECOND trailing closure of the Save alert — `.alert(_:isPresented:actions:message:)`
    /// puts actions first, so closure one is the buttons and closure two is the message.
    ///
    /// ⚠️ The extraction checks ITSELF rather than trusting the ordinal: the gap between the two
    /// closures must contain the `message:` label, so a future overload change that reorders or
    /// drops a closure throws instead of silently scanning the buttons and reporting a missing
    /// sentence. The anchor's file-wide count is asserted too — one ambiguous match and every
    /// assertion above would be measuring a different alert.
    private func saveAlertMessage() throws -> String {
        let text = try source(Self.studio)
        let anchor = ".alert(\"Save project\", isPresented: $showSaveDialog)"
        let hits = text.components(separatedBy: anchor).count - 1
        guard hits == 1 else {
            throw SaveAnchorMissing(reason: """
                `\(anchor)` occurs \(hits)× in \(Self.studio) (expected exactly 1). \
                Re-anchor this scan rather than letting it read an unrelated alert.
                """)
        }
        guard let start = text.range(of: anchor) else {
            throw SaveAnchorMissing(reason: "unreachable: count said 1, range said none")
        }
        let (_, afterActions) = try closure(in: text, from: start.upperBound)
        let gap = text[afterActions...].prefix(while: { $0 != "{" })
        guard gap.contains("message:") else {
            throw SaveAnchorMissing(reason: """
                The Save alert's second trailing closure is no longer labelled `message:` \
                (found "\(gap.trimmingCharacters(in: .whitespacesAndNewlines))"). Re-anchor; \
                do not let this scan read the buttons and report the sentence as missing.
                """)
        }
        let (message, _) = try closure(in: text, from: afterActions)
        return message
    }

    /// The next brace-matched block at or after `index`, plus the position just past its closing
    /// brace. Brace-matched rather than "to the next line at this indentation":
    /// `EchoelStudioView.swift` is ~9,900 lines and deriving scope from FILE ORDER or whitespace
    /// is a mistake this repo has already paid for more than once.
    private func closure(in text: String,
                         from index: String.Index) throws -> (body: String, end: String.Index) {
        guard let open = text[index...].firstIndex(of: "{") else {
            throw SaveAnchorMissing(reason: "no closure follows the Save alert anchor")
        }
        var depth = 0
        var cursor = open
        while cursor < text.endIndex {
            if text[cursor] == "{" { depth += 1 }
            if text[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    let body = String(text[text.index(after: open)..<cursor])
                    return (body, text.index(after: cursor))
                }
            }
            cursor = text.index(after: cursor)
        }
        throw SaveAnchorMissing(reason: "unbalanced braces after the Save alert anchor")
    }

    /// The brace-matched body following `key`, which must end in its opening brace.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        guard let start = text.range(of: key) else {
            throw SaveAnchorMissing(reason: """
                \(relativePath) no longer declares `\(key)`. This scan is anchored on it; \
                re-anchor rather than deleting the assertion.
                """)
        }
        return try closure(in: text, from: text.index(before: start.upperBound)).body
    }
}
