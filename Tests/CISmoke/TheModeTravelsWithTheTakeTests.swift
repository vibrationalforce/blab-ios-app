// TheModeTravelsWithTheTakeTests.swift
// Echoel — #494. `Project.modeRaw` was WRITTEN and never READ. `currentProject()` has stamped
// `ComposerMode(locked: lockBPM).rawValue` into every saved take since this format existed, and
// `Project.mode` has ZERO readers in `Sources/` — so save a Loop take, switch to Flow, reopen it:
// it comes back in Flow while the file says `studioLocked`. `open(_:)` even restores
// `lockedBPM` from the loaded tempo, so the NUMBER travelled while the lock that decides whether
// anyone consults it did not — and in Flow nobody does (`makeComposerInput` passes
// `lockedTempo: lockBPM ? lockedBPM : 90`, and `BioComposer.tempo(for:)` follows the heart on
// `.flowFree`). Ship gate 3 is "Modi (Flow + Loop)"; this is that gate's save/open leg.
//
// ⭐ THIS IS #493 ONE FIELD OVER, and the two differ in exactly the way that matters. There the
// missing field had to be ADDED to `Project`; here it was already on the wire, fully encoded and
// decoded, and only the restore was absent. A field that round-trips perfectly and is never read
// back is invisible to every persistence test that could be written about it — which is why this
// guard's centre of gravity is the WIRING half, not the wire.
//
// ⛔ THE ONE-LINE VERSION OF THIS FIX IS THE BUG, and four of the eight cases exist to keep it
// out. `Project.mode` is `ComposerMode(rawValue: modeRaw) ?? .studioLocked`, and the decoder's
// fallback for an absent key is `""`. So a take saved before this field meant anything reads as
// `.studioLocked` through the accessor, and `lockBPM = (p.mode == .studioLocked)` would LOCK the
// instrument on every legacy take — against a persisted default of `false`. Inventing a fact
// about a file, the same trap #493 avoided. Going through `ComposerMode(rawValue:)` makes "this
// take states no mode" representable, and then the restore deliberately does nothing.
//
// ⚠️ WHAT IS ACTUALLY PINNED HERE, said before anything else. `Project` and `ComposerMode` are
// `public` and pure `Codable`/`RawRepresentable`, so the WIRE and the ENUM halves are real
// behaviour driven end to end — encode, decode, legacy bytes, absent key, the lock→mode mapping.
// The WIRING half (does `open(_:)` read it, does `currentProject()` write it) is a SOURCE SCAN,
// because both live in `private` members of a view no test in this bundle can instantiate.
// Nothing here proves that reopening a Loop take on a device shows a closed lock, or that the
// next generate runs at the saved tempo — those are device checks and both are open.
//
// ⚠️ HONEST GRADING against the pre-#494 tree, transcribed by hand rather than claimed: this file
// DOES compile there (unlike #493's, which named a field that did not exist), so every case has a
// verdict. Exactly TWO are regressions — `testTheOpenSideRestoresTheLockFromTheRawValue` and
// `testTheOpenSideDoesNotUseTheInventingAccessor`, both red because `open(_:)` mentions neither
// `ComposerMode` nor `lockBPM` on that tree. The other SIX are green on both trees and are
// COUNTERWEIGHTS, said plainly rather than dressed up as regressions (#433): they exist to make
// the obvious later "cleanups" fail — switching the restore to `p.mode`, dropping the partner
// `lockedBPM` line as "redundant now that the lock travels", stopping the save side from stamping
// the mode, or giving `flowFree` a raw value that collides with the legacy empty-string sentinel.
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING here, and that is MEASURED, not assumed (#484 and #485
// each had to retract the stronger claim): raw vs stripped differ on **1 of 5** source-scan
// verdicts. The retraction comment this slice writes into `open(_:)` quotes
// `lockBPM = (p.mode == .studioLocked)` verbatim to explain why that form is wrong, so the
// negative scan would be RED on CORRECT code without the stripper. The #486/#491 collision again:
// this repo writes down what it removed, and a negative scan necessarily meets its own obituary.

import XCTest
@testable import Echoelmusic

final class TheModeTravelsWithTheTakeTests: XCTestCase {

    // MARK: - the wire (real behaviour)

    private func take(modeRaw: String) -> Project {
        Project(
            name: "Loop", styleRaw: "dubTechno", keyRoot: 0, scaleRaw: "minor", bpm: 124,
            modeRaw: modeRaw, fxCharacterRaw: "auto", loopBars: 8, a4Hz: 440,
            toneSystemID: "edo12", artist: "Echoel",
            patch: SynthPatch(name: "Default"),
            notes: [Note(pitch: 60, startStep: 0, lengthSteps: 2, velocity: 0.7)],
            drumSteps: [], drumAccents: []
        )
    }

    /// Round-trip. Cheap, and it is the premise every other case leans on: if the wire ever
    /// stopped carrying the mode, the restore below would be reading a field that is always empty
    /// and this whole file would be green about nothing.
    func testTheModeSurvivesASaveAndOpen() throws {
        for raw in [ComposerMode.studioLocked.rawValue, ComposerMode.flowFree.rawValue] {
            let data = try JSONEncoder().encode(take(modeRaw: raw))
            let back = try JSONDecoder().decode(Project.self, from: data)
            XCTAssertEqual(back.modeRaw, raw, "a saved take must state the mode it was played in")
        }
    }

    /// THE CASE THAT NAMES THE TRAP. A take saved before this field meant anything decodes to
    /// `""`, which is not a `ComposerMode` — so the restore must see "states nothing" and leave
    /// the player's current choice alone. The second assertion is the trap itself, asserted
    /// rather than described: the convenience accessor INVENTS `.studioLocked` for that same
    /// take, so a restore written through `p.mode` would lock every legacy file on open.
    func testALegacyTakeStatesNoModeAndTheAccessorInventsOne() throws {
        let data = try JSONEncoder().encode(take(modeRaw: ComposerMode.flowFree.rawValue))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Project must encode as a JSON object")
        object.removeValue(forKey: "modeRaw")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(Project.self, from: legacy)

        XCTAssertEqual(back.modeRaw, "", "an absent key must decode to the empty sentinel")
        XCTAssertNil(ComposerMode(rawValue: back.modeRaw),
                     "the empty sentinel must NOT be a legal mode — that is what makes "
                     + "\"this take states nothing\" representable at the restore site")
        XCTAssertEqual(back.mode, .studioLocked,
                       "documenting the trap, not endorsing it: `Project.mode` invents "
                       + "`.studioLocked` for a take that states nothing. Restoring the lock "
                       + "through this accessor would lock every pre-#494 take on open.")
    }

    /// Counterweight on the enum. The empty string is the legacy sentinel, so neither case may
    /// ever spell itself that way — a rename that did would silently turn "states nothing" into
    /// "states Flow", and the case above would keep passing while meaning the opposite.
    func testNeitherModeIsSpelledAsTheLegacySentinel() {
        XCTAssertFalse(ComposerMode.studioLocked.rawValue.isEmpty)
        XCTAssertFalse(ComposerMode.flowFree.rawValue.isEmpty)
        XCTAssertNotEqual(ComposerMode.studioLocked.rawValue, ComposerMode.flowFree.rawValue)
    }

    /// Counterweight on the mapping this slice inverts. The restore computes
    /// `lockBPM = (savedMode == .studioLocked)`; that is only correct while `init(locked:)` is
    /// its inverse. Pinned here so a later edit to one of the two goes red instead of quietly
    /// making save and open disagree about which mode "locked" means.
    func testTheLockAndTheModeAreInversesOfEachOther() {
        XCTAssertEqual(ComposerMode(locked: true), .studioLocked)
        XCTAssertEqual(ComposerMode(locked: false), .flowFree)
        for locked in [true, false] {
            XCTAssertEqual(ComposerMode(locked: locked) == .studioLocked, locked,
                           "the restore's expression must round-trip the save's")
        }
    }

    // MARK: - the wiring (source scans)

    /// THE REGRESSION. `open(_:)` must derive the lock from the RAW value.
    func testTheOpenSideRestoresTheLockFromTheRawValue() throws {
        let body = try declarationBody(of: "private func open(_ p: Project) {",
                                       in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertFalse(body.isEmpty, "empty body — the anchor matched nothing useful (#367)")
        XCTAssertTrue(body.contains("ComposerMode(rawValue: p.modeRaw)"),
                      "opening a take must read the mode it states, or the Flow/Loop half of "
                      + "ship gate 3 does not survive a save")
        XCTAssertTrue(body.contains("lockBPM = (savedMode == .studioLocked)"),
                      "…and must turn it back into the one lock the whole app reads")
    }

    /// THE SECOND REGRESSION, and the reason the stripper is load-bearing: the tempting form is
    /// present in this very body as a retraction comment.
    func testTheOpenSideDoesNotUseTheInventingAccessor() throws {
        let body = try declarationBody(of: "private func open(_ p: Project) {",
                                       in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertFalse(body.isEmpty, "empty body — the anchor matched nothing useful (#367)")
        XCTAssertFalse(body.contains("p.mode =="),
                       "`Project.mode` falls back to `.studioLocked`, so restoring through it "
                       + "locks every legacy take. Read `p.modeRaw` through "
                       + "`ComposerMode(rawValue:)` instead.")
    }

    /// Counterweight: the save side must keep stating the mode. Without this the two regressions
    /// above stay green on a tree that has stopped writing the field at all — a restore reading a
    /// value nobody records, which is the #343 shape.
    func testTheSaveSideStillStatesTheMode() throws {
        let body = try declarationBody(
            of: "private func currentProject(named name: String? = nil) -> Project {",
            in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertFalse(body.isEmpty, "empty body — the anchor matched nothing useful (#367)")
        XCTAssertTrue(body.contains("ComposerMode(locked: lockBPM).rawValue"),
                      "a take must record which mode it was played in")
    }

    /// Counterweight: the lock and its tempo are a PAIR. `lockedBPM` is only consulted while the
    /// lock is on, so the obvious later cleanup — "the mode travels now, drop the tempo line" —
    /// would restore a locked take with the previous project's BPM.
    func testTheLockAndItsTempoAreRestoredTogether() throws {
        let body = try declarationBody(of: "private func open(_ p: Project) {",
                                       in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertFalse(body.isEmpty, "empty body — the anchor matched nothing useful (#367)")
        XCTAssertTrue(body.contains("lockedBPM = loadedTempo"),
                      "restoring the lock without its tempo hands a locked take the previous "
                      + "project's BPM")
    }

    // MARK: - source access

    private struct ModeAnchorMissing: Error { let reason: String }

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
            throw ModeAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body following `key`, which must end in its opening brace. Brace-matched
    /// rather than "from here to the next declaration": `EchoelStudioView.swift` is ~9,900 lines
    /// and deriving scope from FILE ORDER is a mistake this repo has already paid for more than
    /// once.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        guard let start = text.range(of: key) else {
            throw ModeAnchorMissing(reason: """
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
        throw ModeAnchorMissing(reason: "Unbalanced braces after `\(key)` in \(relativePath).")
    }
}
