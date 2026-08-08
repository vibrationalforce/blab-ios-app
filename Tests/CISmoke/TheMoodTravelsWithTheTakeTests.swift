// TheMoodTravelsWithTheTakeTests.swift
// Echoel — #275 slice 2. Slice 1 gave the eight mood dials persistence at all; it was GLOBAL.
// So opening a saved take restored its genre, key, scale, tempo, tuning, Flow/Loop mode, sound
// and raw bars — and left whatever mood happened to be dialled in on the instrument. A take
// saved at tension 0.9 came back at whatever the last session ended on, which on the composer's
// own terms is a different piece: `mood` reaches `BioComposer.Input` beside `style` and `key`.
//
// ⭐ AND THE DEFECT WAS INVISIBLE TO EVERY EXISTING GUARD, which is why it survived #493 (tone
// system), #494 (mode) and #217 (raw bars) — three slices in a row whose whole subject was "what
// travels with a take". Persistence guards ask whether a field round-trips; mood had NO field to
// round-trip. A value that is absent from the wire is absent from every wire assertion (#494's
// `modeRaw` was the mirror case: perfectly round-tripping and never read back).
//
// ⚠️ WHAT IS ACTUALLY PINNED HERE, said before anything else. The WIRE and DECISION halves are
// real behaviour driven end to end — `Project` is `public` and pure `Codable`, `MoodStorage` and
// `MoodProfile` are Foundation-only value types, so encode/decode and the tolerance rule run
// through shipped code. The WIRING half is a SOURCE SCAN: `currentProject()` and `open(_:)` are
// `private` members of a view this bundle cannot instantiate. **That a saved take really comes
// back with its mood on the device is a device check and it is OPEN.**
//
// ⭐ THE COUNTERWEIGHTS ARE THE CONTENT (#343). A guard that only asserts "the mood round-trips"
// stays green on a tree that kept the field and lost the RULES around it — and every one of those
// rules is a decision someone will later read as noise:
//   · the restore is CONDITIONAL, so a legacy take does not flatten eight dials the player set;
//   · the wire key is ABSENT rather than `null` when a take states no mood;
//   · the tolerance is `MoodStorage`'s ONE rule, not a second copy on `Project` (#416);
//   · `Project.init` gives `moodFields` NO default, so a forgetting call site is a compile
//     error rather than a silent `nil` (#440/#443).
//
// ⚠️ HONEST GRADING (#433), and it is the #464 situation said plainly: this file **cannot be
// graded against the parent tree at all** — every case names `Project.moodFields`,
// `Project.mood` or `MoodStorage.fields(from:)`, none of which exist there, so the bundle does
// not compile and NO assertion has a verdict. Transcribed by hand (a Python rebuild of
// `SourceText.codeOnly` plus the brace matcher, run against `git show HEAD:` and the worktree):
// **three** source needles are red on the parent for their NAMED reason (`currentProject()` has
// no `moodFields:` argument; `open(_:)` has no mood restore at all; `Project.init` has no
// `moodFields` parameter). **TWO** are green on both trees and are counterweights — and one of
// those is green on the parent only TRIVIALLY, because a method with no mood code at all cannot
// contain a mood default. That is worth saying rather than counting: it is a forward guard, not
// a regression. The behaviour cases drive symbols this same commit adds — booking them as
// regressions would be the #433 defect in the flattering direction.
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING here, and that is MEASURED rather than assumed
// (#484/#485 each had to retract the stronger claim, #486 twice — and the first draft of THIS
// header made the same overclaim, caught by measuring before committing): raw vs stripped differ
// on **1 of 10** needle verdicts across both trees. The flipping one is `?? MoodProfile()`, which
// this slice writes VERBATIM into a retraction comment inside `open(_:)` to explain why that
// spelling is wrong — so a raw-text scan would be RED on CORRECT code. The #486/#491 collision
// once more: this repo writes down what it removed, and a negative scan necessarily runs into
// its own obituary.

import XCTest
@testable import Echoelmusic

final class TheMoodTravelsWithTheTakeTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let project = "Sources/Echoelmusic/Core/Project.swift"

    // MARK: - fixtures

    /// A mood no default produces: every field is off its factory value, so "it round-tripped"
    /// cannot be satisfied by a `MoodProfile()` appearing from anywhere.
    private func distinctMood() -> MoodProfile {
        MoodProfile(liveliness: 0.11, darkness: 0.22, tension: 0.33, romance: 0.44,
                    weird: 0.55, virtuosity: 0.66, syncopation: 0.77, humanize: 0.88)
    }

    private func take(moodFields: [String: Float]?) -> Project {
        Project(
            name: "Take", styleRaw: "dubTechno", keyRoot: 2, scaleRaw: "minor", bpm: 96,
            modeRaw: ComposerMode.studioLocked.rawValue, fxCharacterRaw: "auto", loopBars: 4,
            a4Hz: 440, toneSystemID: "edo12", moodFields: moodFields, artist: "Echoel",
            patch: SynthPatch(name: "Default"), notes: [],
            rawTake: nil, drumSteps: [], drumAccents: []
        )
    }

    private func roundTrip(_ project: Project) throws -> Project {
        try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
    }

    private func keys(of project: Project) throws -> Set<String> {
        let data = try JSONEncoder().encode(project)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   "Project must encode as a JSON object")
        return Set(object.keys)
    }

    // MARK: - the wire (real behaviour)

    /// THE POINT. Eight dials in, eight dials out, through the shipped encoder.
    func testTheMoodRoundTripsThroughTheWire() throws {
        let mood = distinctMood()
        let reopened = try roundTrip(take(moodFields: MoodStorage.fields(from: mood)))
        let restored = try XCTUnwrap(reopened.mood,
                                     "a take saved WITH a mood must state one when reopened")
        XCTAssertEqual(restored, mood,
                       "all eight dials must survive the take; a partial restore is a different "
                       + "piece, because `mood` reaches `BioComposer.Input` beside style and key")
    }

    /// A take that states no mood must write NO KEY, not `null`. `encodeIfPresent` is what makes
    /// "this file says nothing about mood" representable at all — a `null` would be a third state
    /// every reader would have to handle, and an older build would read it as corruption.
    func testATakeWithoutAMoodWritesNoKey() throws {
        XCTAssertFalse(try keys(of: take(moodFields: nil)).contains("moodFields"),
                       "`nil` must encode as an ABSENT key — see `encodeIfPresent` on `Project`")
        XCTAssertTrue(try keys(of: take(moodFields: MoodStorage.fields(from: distinctMood())))
                        .contains("moodFields"),
                      "a take that DOES state a mood must put it on the wire, or the round trip "
                      + "above is passing for the wrong reason")
    }

    /// THE LEGACY CASE, and the reason the accessor is `MoodProfile?` rather than
    /// `?? MoodProfile()`. A take written before this slice states nothing about mood; reporting
    /// a neutral profile would be inventing a fact about a file (#424/#426/#433/#461), and the
    /// open path would then flatten eight dials the player had set.
    func testALegacyTakeStatesNoMoodRatherThanAFlatOne() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(take(moodFields: MoodStorage.fields(from: distinctMood())))
            ) as? [String: Any],
            "Project must encode as a JSON object")
        json.removeValue(forKey: "moodFields")
        let legacy = try JSONDecoder().decode(
            Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.moodFields, "an absent key must decode as absent, never as a default")
        XCTAssertNil(legacy.mood,
                     "`Project.mood` must stay `nil` for a take that names no mood — a neutral "
                     + "`MoodProfile()` here would be indistinguishable from a player who really "
                     + "dialled every knob to factory, and the open path acts on the difference")
    }

    /// COUNTERWEIGHT on the shared rule (#416). A map missing seven fields costs those seven
    /// nothing but their stored value — the tolerance is `MoodStorage`'s, so `Project` reading it
    /// must show the SAME field-by-field fallback rather than a second implementation.
    func testAPartialMapLeavesTheOtherSevenAtFactory() throws {
        let reopened = try roundTrip(take(moodFields: ["tension": 0.9]))
        let restored = try XCTUnwrap(reopened.mood, "a stated map is a stated mood, even partial")
        XCTAssertEqual(restored.tension, 0.9, accuracy: 1e-6,
                       "the one field the file names must survive")
        let factory = MoodProfile()
        XCTAssertEqual(restored.liveliness, factory.liveliness, accuracy: 1e-6)
        XCTAssertEqual(restored.humanize, factory.humanize, accuracy: 1e-6,
                       "an absent field falls back to ITS factory value, not to zero — 0 is a "
                       + "real setting (\"machine-exact\"), which is why `clamped(to:)` is the "
                       + "wrong tool and `MoodStorage` says so at length")
    }

    /// COUNTERWEIGHT, and the one case JSON cannot reach. `Project` can be constructed in memory
    /// with a non-finite value (a peer payload, a migration, a future non-JSON door), and when it
    /// is, the field must fall back rather than clamp to 0 — mapping "unreadable" onto "the user
    /// asked for none of it" is the fabricated-number class. Driving it here is only possible
    /// BECAUSE the rule lives in `MoodStorage.profile(from:)` instead of inside `decode`.
    func testANonFiniteFieldFallsBackRatherThanClampingToZero() throws {
        let restored = try XCTUnwrap(take(moodFields: ["humanize": .nan]).mood)
        XCTAssertEqual(restored.humanize, MoodProfile().humanize, accuracy: 1e-6,
                       "NaN must read as \"this field is unreadable\", not as 0")
        let high = try XCTUnwrap(take(moodFields: ["tension": 5.0]).mood)
        XCTAssertEqual(high.tension, 1.0, accuracy: 1e-6,
                       "a FINITE value outside 0…1 can only be corruption and IS clamped — the "
                       + "two cases are deliberately different and both belong to `MoodStorage`")
    }

    // MARK: - the wiring (source scans)

    /// REGRESSION. The wire proves `Project` CAN carry the mood; only this proves the Save door
    /// FILLS it. Without it a tree that passed `moodFields: nil` keeps every wire assertion green
    /// while no saved file ever contains a mood.
    func testTheSaveDoorFillsTheMood() throws {
        let body = try declarationBody(
            of: "private func currentProject(named name: String? = nil) -> Project {",
            in: Self.studio)
        XCTAssertFalse(body.isEmpty, "empty body — the anchor matched nothing useful (#367)")
        XCTAssertTrue(body.contains("moodFields: MoodStorage.fields(from: mood)"),
                      "the Save door must record the mood, and through the SHARED field map — "
                      + "an inline literal here would be a second copy of the eight names (#416)")
    }

    /// REGRESSION plus the counterweight that matters most, in one place because they are two
    /// halves of one line: the restore must exist AND must be conditional. `?? MoodProfile()`
    /// looks like the tidier spelling and would silently flatten a player's dials on every take
    /// written before this slice.
    func testOpeningATakeRestoresTheMoodAndOnlyWhenTheTakeStatesOne() throws {
        let body = try declarationBody(of: "private func open(_ p: Project) {", in: Self.studio)
        XCTAssertFalse(body.isEmpty, "empty body — the anchor matched nothing useful (#367)")
        XCTAssertTrue(body.contains("if let m = p.mood { mood = m }"),
                      "opening a take must adopt its mood, the way it already adopts genre, key "
                      + "and scale")
        XCTAssertFalse(body.contains("?? MoodProfile()"),
                       "a legacy take states NO mood; defaulting here would overwrite eight dials "
                       + "the player set with a fact the file never contained")
    }

    /// COUNTERWEIGHT on the constructor (#440/#443). A default would let a future `Project.init`
    /// call site forget the mood and compile — and a forgotten argument appears in no diff. The
    /// compile error is the whole mechanism, so the ABSENCE of a default is the assertion.
    func testTheConstructorForcesEveryCallSiteToDecide() throws {
        let text = try source(Self.project)
        XCTAssertTrue(text.contains("moodFields: [String: Float]?,"),
                      "`Project.init` must take the mood explicitly")
        XCTAssertFalse(text.contains("moodFields: [String: Float]? = nil"),
                       "no default: a call site that forgets the mood must fail to compile, not "
                       + "silently save a take without one")
    }

    // MARK: - source access

    private struct MoodAnchorMissing: Error { let reason: String }

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
            throw MoodAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body following `key`, which must end in its opening brace. Brace-matched
    /// rather than "to the next line at this indentation": `EchoelStudioView.swift` is ~9,900
    /// lines and deriving scope from FILE ORDER or whitespace is a mistake this repo has paid for
    /// more than once.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        let hits = text.components(separatedBy: key).count - 1
        guard hits == 1 else {
            throw MoodAnchorMissing(reason: """
                `\(key)` occurs \(hits)× in \(relativePath) (expected exactly 1). Re-anchor this \
                scan rather than letting it read an unrelated declaration.
                """)
        }
        guard let start = text.range(of: key) else {
            throw MoodAnchorMissing(reason: "unreachable: count said 1, range said none")
        }
        guard let open = text[text.index(before: start.upperBound)...].firstIndex(of: "{") else {
            throw MoodAnchorMissing(reason: "no body follows `\(key)`")
        }
        var depth = 0
        var cursor = open
        while cursor < text.endIndex {
            if text[cursor] == "{" { depth += 1 }
            if text[cursor] == "}" {
                depth -= 1
                if depth == 0 { return String(text[text.index(after: open)..<cursor]) }
            }
            cursor = text.index(after: cursor)
        }
        throw MoodAnchorMissing(reason: "unbalanced braces after `\(key)`")
    }
}
