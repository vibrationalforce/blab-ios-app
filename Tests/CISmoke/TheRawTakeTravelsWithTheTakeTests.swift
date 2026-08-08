// TheRawTakeTravelsWithTheTakeTests.swift
// Echoel — #217. A Mix fader on a SAVED take composed a different piece instead of rebalancing
// the one you were listening to. `EchoelStudioView` keeps the composer's pre-mix bars in
// `@State lastRawTake` so `rebalanceTake()` can RE-BAKE the existing take at the new level
// (#174); `@State` is per app session, and `open(_:)` restored an already-glued take through
// `pianoRoll.load(p.notes)` without it. So on every opened project that state was `nil`, and
// `rebalanceTake()`'s documented fallback is `recomposeIfRunning()` — the one place a level
// control is most obviously what you reach for was the one place it replaced the music. Its own
// comment named persisting these bars as the answer. This slice persists them.
//
// ⭐ THE GENRE TRAVELS WITH THE BARS, IN ONE VALUE, and that is why `Project.RawTake` is a nested
// struct rather than two optional fields side by side. `rebalanceTake()` re-glues with
// `take.genre`, NOT the picker's current `style` — a take must be re-glued in the genre it was
// COMPOSED in, even after the user has picked another one. Two independent optionals would make
// "bars without their genre" representable, and the only thing a reader could do with that state
// is the exact bug the pairing prevents. Three of the cases below exist to keep that pairing.
//
// ⚠️ WHAT IS ACTUALLY PINNED HERE, said before anything else. `Project` and `Note` are `public`
// and pure `Codable`, so the WIRE and the DECISION halves are real behaviour driven end to end —
// round-trip, a legacy file, an absent key, a structurally broken payload, one undecodable note,
// an unknown genre, and each of `rebakeSource`'s three exclusions. The WIRING half (does
// `currentProject()` write it, does `open(_:)` restore it) is a SOURCE SCAN, because both live in
// `private` members of a view no test in this bundle can instantiate. **Nothing here proves that
// moving a Mix fader on a reopened take rebalances it on a device — that is a device check and it
// is open.**
//
// ⚠️ HONEST GRADING against the pre-#217 tree, and it is the #464 situation said plainly rather
// than dressed up: this file **cannot be graded there at all** — it names `Project.RawTake`,
// `rawTake:` and `rebakeSource`, none of which exist on that tree, so the bundle does not compile
// and NO assertion has a verdict. Transcribed by hand instead: the TWO source scans are
// regressions for their stated reason (`currentProject()` has no `rawTake:` argument there, and
// `open(_:)` has no `lastRawTake` assignment at all). The behaviour cases drive a type this same
// commit creates and could never have been red — booking them as regressions would be the #433
// defect in the flattering direction. The remaining two are COUNTERWEIGHTS, green on both trees:
// the fader must keep re-gluing in `take.genre`, and the generate site must keep recording the
// bars — without them the two scans stay green on a tree that restores a value nobody records,
// which is the #343 shape.
//
// ⚠️ `SourceText.codeOnly` is PROPHYLACTIC here, and that is MEASURED rather than assumed (#484
// and #485 each had to retract the stronger claim, #486 twice): raw vs stripped differ on **0 of
// 4** source-scan verdicts on both trees. It stays because #453 made one shared definition of
// "code, not prose" for the whole blocking bundle, and it stops being prophylactic the moment
// somebody writes a retraction here that quotes one of these needles verbatim — which is exactly
// how #486 and #491 became load-bearing.

import XCTest
@testable import Echoelmusic

final class TheRawTakeTravelsWithTheTakeTests: XCTestCase {

    // MARK: - fixtures

    private func note(_ pitch: Int, _ step: Int, velocity: Float = 0.7) -> Note {
        Note(pitch: pitch, startStep: step, lengthSteps: 2, velocity: velocity)
    }

    private func take(rawTake: Project.RawTake?) -> Project {
        Project(
            name: "Take", styleRaw: "dubTechno", keyRoot: 0, scaleRaw: "minor", bpm: 124,
            modeRaw: "studioLocked", fxCharacterRaw: "auto", loopBars: 2, a4Hz: 440,
            toneSystemID: "edo12", artist: "Echoel",
            patch: SynthPatch(name: "Default"),
            notes: [note(60, 0)],
            rawTake: rawTake,
            drumSteps: [], drumAccents: []
        )
    }

    private var twoBars: Project.RawTake {
        Project.RawTake(
            styleRaw: MusicStyle.dubTechno.rawValue,
            bars: [[note(48, 0), note(55, 4)], [note(50, 0)]])
    }

    private func json(_ p: Project) throws -> [String: Any] {
        let data = try JSONEncoder().encode(p)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any],
                             "Project must encode as a JSON object")
    }

    private func decode(_ object: [String: Any]) throws -> Project {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Project.self, from: data)
    }

    // MARK: - the wire (real behaviour)

    /// Round-trip. Cheap, and it is the premise every other case leans on: if the bars ever
    /// stopped travelling, the restore below would be reading a field that is always empty and
    /// this whole file would be green about nothing.
    func testTheComposerBarsSurviveASaveAndOpen() throws {
        let back = try decode(try json(take(rawTake: twoBars)))
        let raw = try XCTUnwrap(back.rawTake, "the composer's bars must survive a save")
        XCTAssertEqual(raw.styleRaw, MusicStyle.dubTechno.rawValue,
                       "the bars must carry the genre they were composed in")
        XCTAssertEqual(raw.bars.count, 2, "bar count is the loop order — it must not collapse")
        XCTAssertEqual(raw.bars.map(\.count), [2, 1])
        XCTAssertEqual(raw.bars[0].map(\.pitch), [48, 55])
        XCTAssertEqual(raw.bars[1].map(\.pitch), [50])
        XCTAssertEqual(raw.bars[0][0].velocity, 0.7, accuracy: 1e-6,
                       "the PRE-MIX velocity is the whole point — it is what a fader re-bakes "
                       + "from, and a mixer level baked into it could never be undone")
    }

    /// A take written before this field genuinely states no raw bars, and `nil` is the only
    /// honest reading — there is nothing to fall back to, because `notes` is the ONE sounding
    /// bar whose velocities already carry a mixer level. The second half is the load-bearing
    /// one: everything else about that file must come back untouched.
    func testALegacyTakeStatesNoRawBarsAndLosesNothingElse() throws {
        var object = try json(take(rawTake: twoBars))
        object.removeValue(forKey: "rawTake")
        let back = try decode(object)

        XCTAssertNil(back.rawTake, "an absent key must read as \"this take states no raw bars\"")
        XCTAssertEqual(back.notes.map(\.pitch), [60],
                       "the take you actually hear must be untouched by the new field")
        XCTAssertEqual(back.bpm, 124)
        XCTAssertEqual(back.toneSystemID, "edo12")
    }

    /// `encodeIfPresent`, for the `toneSystemID` reason: a take that states no raw bars writes
    /// NO key, so re-reading it yields `nil` again rather than a JSON null.
    func testATakeWithNoRawBarsWritesNoKeyAtAll() throws {
        let object = try json(take(rawTake: nil))
        XCTAssertFalse(object.keys.contains("rawTake"),
                       "\"states nothing\" must be an absent key, not a null")
    }

    /// THE COUNTERWEIGHT THAT MATTERS MOST. A structurally broken raw take — a truncated write, a
    /// future shape — must not take the take WITH it. Without the outer `try?` this throws out of
    /// `Project.init(from:)`, and `ProjectStore`'s own `try?` turns that into the user's entire
    /// saved take vanishing: the exact bug `LossyDecoded` exists for, re-opened by adding an
    /// un-hardened field to a hardened struct.
    func testABrokenRawTakeDoesNotTakeTheTakeWithIt() throws {
        var object = try json(take(rawTake: twoBars))
        // A payload that is shaped wrong rather than typed wrong: the key is there, the genre
        // reads fine, and `bars` is a number. That is what a truncated write or a future shape
        // looks like from here, and it throws from INSIDE `RawTake.init(from:)`.
        let broken: [String: Any] = ["styleRaw": MusicStyle.dubTechno.rawValue, "bars": 42]
        object["rawTake"] = broken
        let back = try decode(object)

        XCTAssertNil(back.rawTake, "an unreadable raw take cannot be re-baked from — say so")
        XCTAssertEqual(back.notes.map(\.pitch), [60],
                       "…and losing it must cost NOTHING else. A fader that falls back to "
                       + "composing is a smaller failure than a take that disappears.")
        XCTAssertEqual(back.name, "Take")
        XCTAssertEqual(back.bpm, 124)
    }

    /// The INNER layer, and the one that proves the two are doing different jobs: one note a
    /// future build wrote with an unknown `NoteRole` becomes one missing note, not a lost
    /// arrangement. If this ever starts behaving like the case above — whole raw take gone — the
    /// element tolerance has been dropped.
    func testOneUndecodableNoteCostsOnlyThatNote() throws {
        var object = try json(take(rawTake: twoBars))
        var raw = try XCTUnwrap(object["rawTake"] as? [String: Any])
        var bars = try XCTUnwrap(raw["bars"] as? [[Any]])
        var firstBar = bars[0]
        var firstNote = try XCTUnwrap(firstBar[0] as? [String: Any])
        firstNote["role"] = "tuba"          // not a NoteRole — the synthesized decoder throws
        firstBar[0] = firstNote
        bars[0] = firstBar
        raw["bars"] = bars
        object["rawTake"] = raw

        let back = try decode(object)
        let survived = try XCTUnwrap(back.rawTake,
                                     "one bad note must not cost the whole arrangement — that is "
                                     + "the difference between the inner and the outer layer")
        XCTAssertEqual(survived.bars.count, 2, "bars keep their POSITIONS — the outer array is "
                       + "the loop order")
        XCTAssertEqual(survived.bars[0].map(\.pitch), [55], "only the undecodable note is gone")
        XCTAssertEqual(survived.bars[1].map(\.pitch), [50], "…and the other bars are untouched")
    }

    // MARK: - the decision (real behaviour)

    /// A take from a build that knows a `MusicStyle` this one does not. Re-gluing it in some
    /// OTHER genre is precisely the defect `rebalanceTake()`'s "`take.genre`, NOT `style`"
    /// comment prevents, so "cannot re-bake" is the only honest answer. This is also the
    /// counterweight against the tempting later tidy-up of giving `RawTake.style` the
    /// `?? .dubTechno` fallback its `Project.style` neighbour carries.
    func testAnUnknownGenreMeansCannotReBakeRatherThanSomeOtherGenre() throws {
        let raw = Project.RawTake(styleRaw: "gregorianTechno", bars: [[note(48, 0)]])
        XCTAssertNil(raw.style, "an unknown genre must not resolve to a different one")
        XCTAssertNil(take(rawTake: raw).rebakeSource,
                     "…and a take that cannot be re-glued in its own genre must not be re-baked "
                     + "at all")
    }

    /// The three exclusions, each for its own reason and none of them interchangeable, plus the
    /// good case. Driving them here rather than scanning the open site is the whole reason the
    /// decision lives on `Project`: it makes "opening must not leave the previous session's bars
    /// in place" hold by CONSTRUCTION at the call site.
    func testRebakeSourceExcludesEachUnusableTakeAndAdmitsAGoodOne() throws {
        XCTAssertNil(take(rawTake: nil).rebakeSource,
                     "no raw take — every file written before #217")
        XCTAssertNil(take(rawTake: Project.RawTake(styleRaw: MusicStyle.dubTechno.rawValue,
                                                   bars: [])).rebakeSource,
                     "empty bars — nothing to re-bake")
        XCTAssertNil(take(rawTake: Project.RawTake(styleRaw: "", bars: [[note(48, 0)]]))
                        .rebakeSource,
                     "the empty genre sentinel is not a genre")

        let good = try XCTUnwrap(take(rawTake: twoBars).rebakeSource,
                                 "a complete raw take must be re-bakeable")
        XCTAssertEqual(good.genre, .dubTechno)
        XCTAssertEqual(good.bars.map { $0.map(\.pitch) }, [[48, 55], [50]])
    }

    /// Counterweight against a clamp that would look like tidying up. `MusicStyle.offered` is the
    /// curated PICKER roster; these bars must be re-glued in the genre they were COMPOSED in,
    /// offered or not. `.trap` was curated out of the picker on 2026-07-24 and still exists — a
    /// take saved while it was offered must stay re-bakeable.
    func testAGenreThatIsNoLongerOfferedCanStillBeReBaked() throws {
        XCTAssertFalse(MusicStyle.offered.contains(.trap),
                       "premise: `.trap` is a real genre that the picker no longer offers")
        let raw = Project.RawTake(styleRaw: MusicStyle.trap.rawValue, bars: [[note(48, 0)]])
        let source = try XCTUnwrap(take(rawTake: raw).rebakeSource,
                                   "re-baking follows the genre the take was COMPOSED in, not "
                                   + "the curated picker roster")
        XCTAssertEqual(source.genre, .trap)
    }

    // MARK: - the wiring (source scans)

    /// THE FIRST REGRESSION. A saved take must state its composer bars.
    func testTheSaveSideStatesTheComposerBars() throws {
        let body = try declarationBody(
            of: "private func currentProject(named name: String? = nil) -> Project {",
            in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertFalse(body.isEmpty, "empty body — the anchor matched nothing useful (#367)")
        XCTAssertTrue(body.contains("rawTake:"),
                      "a take saved without its raw bars cannot be re-baked after an open, and "
                      + "the Mix fader goes back to composing a different piece")
    }

    /// THE SECOND REGRESSION, and the one that names the shape. The restore must be ONE TOTAL
    /// assignment: anything that leaves this state untouched on a take with no usable raw bars
    /// keeps the SESSION's bars in place, and the first fader move then re-bakes THAT piece over
    /// the take just opened — a worse defect than the one this slice fixes.
    func testTheOpenSideRestoresTheRebakeSourceTotally() throws {
        let body = try declarationBody(of: "private func open(_ p: Project) {",
                                       in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertFalse(body.isEmpty, "empty body — the anchor matched nothing useful (#367)")
        XCTAssertTrue(body.contains("lastRawTake = p.rebakeSource"),
                      "opening a take must replace the re-bake source outright — a conditional "
                      + "restore leaves the previous session's bars behind")
    }

    /// Counterweight: the fader must keep re-gluing in the genre the take was COMPOSED in. This
    /// is the invariant the whole nested-struct pairing exists to protect, and it is green on
    /// both trees — it is here so that a later "use the current style, it's right there" edit
    /// goes red instead of quietly re-scoring saved takes in whatever genre is on screen.
    func testTheFaderStillReGluesInTheGenreTheTakeWasComposedIn() throws {
        let body = try declarationBody(of: "private func rebalanceTake() {",
                                       in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertFalse(body.isEmpty, "empty body — the anchor matched nothing useful (#367)")
        XCTAssertTrue(body.contains("genre: take.genre"),
                      "re-gluing with the picker's current genre would re-score a saved take in "
                      + "a genre it was never composed in")
    }

    /// Counterweight: the generate site must keep RECORDING the bars. Without this the two scans
    /// above stay green on a tree that restores a value nobody writes — a save side stating an
    /// always-empty field, which is the #343 shape.
    func testTheGenerateSiteStillRecordsTheRawTake() throws {
        let text = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(text.contains("lastRawTake = (genre:"),
                      "something must still capture the composer's bars at generate time, or "
                      + "there is nothing for the save side to state")
    }

    // MARK: - source access

    private struct RawTakeAnchorMissing: Error { let reason: String }

    /// Comment-stripped source (#453 — one shared definition of "code, not prose"), a SKIP when
    /// there is no checkout, and a FAILURE when the file itself moved (#454: a skip passes CI, so
    /// "no tree" may skip and "the thing I guard was renamed" may not). The skip gates on the
    /// DIRECTORY, never per file (#475).
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw RawTakeAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body following `key`, which must end in its opening brace. Brace-matched
    /// rather than "from here to the next declaration": `EchoelStudioView.swift` is ~9,900 lines
    /// and deriving scope from FILE ORDER is a mistake this repo has already paid for.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        guard let start = text.range(of: key) else {
            throw RawTakeAnchorMissing(reason: """
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
        throw RawTakeAnchorMissing(reason: "Unbalanced braces after `\(key)` in \(relativePath).")
    }
}
