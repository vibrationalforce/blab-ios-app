//
//  TheMeterReadersAreNamedWhereTheyAreClearedTests.swift
//  Echoelmusic — CISmoke (blocking)
//
//  WHAT THIS IS (§1): a SOURCE-TEXT SCAN. It proves that a prose note and the code it
//  reasons about still describe the same set of files. It proves NOTHING about rendering,
//  about SwiftUI observation at runtime, or about whether a menu actually stays open —
//  that is a DEVICE PROBE and stays open.
//
//  WHY IT EXISTS (#886, 2026-08-30). `scratchpads/BAUSTELLEN_BOARD.md` carried the
//  architecture-audit note for AU5 ("AudioEngine meter props are a 60 Hz freeze landmine").
//  It cleared the item with a premise: the props are read *only* by `MasterLoudnessGrid`,
//  a visibility-gated leaf, so `EchoelStudioView` never observes them. The CONCLUSION was
//  and is right. The PREMISE went false without anyone touching the note: `SpectralDonutView`
//  reads `masterLevel`/`masterLevelR` too, and #747 gave it a door ("Full screen" in
//  `visualPanel`), so a reader that was unreachable when the note was written now renders.
//
//  This is the #756 shape — the conclusion holds, the witness does not — and it is the
//  expensive kind, because a later session uses the premise ("nothing else reads the meters")
//  to clear a DIFFERENT change. Nothing could have gone red: no guard read that note.
//
//  ⚠️ THE LIMIT, STATED BEFORE THE CLAIM (#408). The needle is `.masterLevelR`, the STEREO
//  half, and that is deliberate. `.masterLevel` alone is NOT usable as an anchor: measured
//  across `Sources/` with comments stripped it selects seven files, and five of them read a
//  DIFFERENT property of the same name — `MusicalFrame.masterLevel` (`HeaderMonitors`,
//  `MusicMediaMapping`, `MetalBioView`), plus an `AutomationPlayer` enum case spelled
//  `.masterLevel`. Keying on it would have made this guard red on a correct tree.
//  The cost of the narrower needle is real and is written down rather than hidden: a future
//  view that reads ONLY the mono meter is invisible here. Claim 2 pins the discriminator so
//  the day `MusicalFrame` grows a `masterLevelR` this file says so instead of drifting.
//
//  Also NOT part of the needle: the receiver name. Both readers today spell it
//  `audioEngine.masterLevelR`, and anchoring on that would be tighter — and would silently
//  miss a view that binds the engine under another name. A needle that cannot match the
//  thing it is pointed at is the defect this bundle exists to prevent (#679/#738).
//
//  GRADING AGAINST THE PARENT (§3), transcribed in Python and driven against
//  `git show HEAD:<path>` and the worktree:
//   · claim 1 — REGRESSION. The parent note names `MasterLoudnessGrid` and not
//     `SpectralDonutView`, while the parent SOURCE already contained both readers.
//   · claim 3 — REGRESSION by the same absence (#486: one absence, reported twice, is ONE
//     finding — the parent note has neither "GESCHWISTER" nor "#747").
//   · claims 2 and 4 — COUNTERWEIGHTS, green on both trees. That is the point of them
//     (#343): claim 1 is only meaningful while `masterLevelR` still discriminates, and the
//     AU6 row is only closed while the third `applyBioReactive` owner stays gone.
//

import XCTest

final class TheMeterReadersAreNamedWhereTheyAreClearedTests: XCTestCase {

    private static let board = "scratchpads/BAUSTELLEN_BOARD.md"
    private static let owner = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    /// The AU5 note, delimited by content and not by a line count: a fixed window is unsound
    /// in this repo (#408), and this block grew from 4 lines to 23 in the commit that wrote
    /// this guard.
    private func au5Note() throws -> String {
        let text = try boardText()
        guard let start = text.range(of: "> **AU5**") else {
            throw Anchor(reason: """
                \(Self.board) no longer contains the "> **AU5**" note. It was renamed or \
                removed — re-anchor this scan rather than letting it skip (#454).
                """)
        }
        guard let end = text.range(of: "> PLAUSIBLE/",
                                   range: start.upperBound..<text.endIndex) else {
            throw Anchor(reason: """
                the AU5 note is no longer terminated by the "> PLAUSIBLE/" line. Give this \
                scan a new terminator; do NOT fall back to a character count.
                """)
        }
        return String(text[start.lowerBound..<end.lowerBound])
    }

    // MARK: - 1. every stereo-meter reader is named in the note that cleared the item

    func testEveryMeterReaderIsNamedInTheNoteThatClearedTheItem() throws {
        let note = try au5Note()
        let readers = try stereoMeterReaders()

        XCTAssertFalse(readers.isEmpty, """
            no file under Sources/ reads `.masterLevelR` outside AudioEngine.swift. Either \
            the meter was renamed or this scan stopped matching — a vacuous green here is \
            worse than a red, because the AU5 note would keep clearing itself on nothing.
            """)

        let unnamed = readers.filter { !note.contains($0) }
        XCTAssertTrue(unnamed.isEmpty, """
            \(Self.board)'s AU5 note clears a 60 Hz freeze risk with a premise about WHICH \
            views read the master meters, and it does not name: \(unnamed.joined(separator: ", ")).

            Today's readers, derived from Sources/ with comments stripped: \
            \(readers.joined(separator: ", ")).

            This is not a request to delete the reader. Add it to the note WITH the reason it \
            is safe — the standing argument is that each reader is its own View struct (a real \
            observation boundary) and a SIBLING of the menu host, never its ancestor. If a new \
            reader is an ANCESTOR of a Picker, the freeze law (10.76.41/50) applies and the \
            note's conclusion has to change, not just its list.
            """)
    }

    // MARK: - 2. counterweight — the needle still discriminates (green on both trees)

    func testTheStereoMeterNameBelongsToTheEngineAlone() throws {
        let engine = try codeText(Self.owner)
        XCTAssertTrue(engine.contains("masterLevelR"), """
            `masterLevelR` is no longer declared in AudioEngine.swift. Claim 1 selects files \
            by that name; if the engine dropped it, claim 1 is measuring nothing.
            """)

        let frame = "Sources/Echoelmusic/Core/MusicalFrame.swift"
        if let musical = try? codeText(frame) {
            XCTAssertFalse(musical.contains("masterLevelR"), """
                \(frame) now also declares `masterLevelR`. That breaks the discriminator claim 1 \
                relies on: `masterLevel` alone is ALREADY shared between AudioEngine and \
                MusicalFrame (measured: 7 files, 5 of them the frame's), and the stereo half was \
                the only unambiguous half. Re-anchor claim 1 on the receiver or on a new name \
                before trusting it again.
                """)
        }
    }

    // MARK: - 3. counterweight — the note still carries the reason, not just the list

    func testTheNoteKeepsTheReasonItsConclusionRestsOn() throws {
        let note = try au5Note()
        for token in ["GESCHWISTER", "#747"] {
            XCTAssertTrue(note.contains(token), """
                the AU5 note lost "\(token)". Its conclusion ("no live freeze today") does not \
                rest on the list of readers — it rests on WHERE they sit: siblings of the VJ \
                overlay inside the fullScreenCover's ZStack, not ancestors of it, and on the \
                fact that #747 is what made the second reader reachable at all. A list without \
                that reason is the premise-without-witness defect this file was written for.
                """)
        }
    }

    // MARK: - 4. counterweight — AU6 stays closed only while its premise holds

    func testTheThirdBioOwnerIsStillGone() throws {
        var offenders: [String] = []
        for path in try swiftFiles() {
            guard let code = try? codeText(path) else { continue }
            if code.contains("BioMirror") { offenders.append(path) }
        }
        XCTAssertTrue(offenders.isEmpty, """
            `BioMirror` is back in CODE (not just in the tombstone comment) at: \
            \(offenders.joined(separator: ", ")).

            That name belonged to the AUv3 KVO poll — the THIRD caller of `applyBioReactive`, \
            and the only one that ran off the render thread. Its removal (#121 Slice 1) is what \
            closed audit item AU6 (cross-thread COW hazard on `harmonicAmplitudes`), and \
            `\(Self.board)` now records AU6 as closed on exactly that ground.

            This does NOT forbid the work (#364). It says: if a third owner comes back, the AU6 \
            row and the `EchoelDDSP.swift` header invariant must be reopened in the SAME commit.
            """)
    }

    // MARK: - source access

    private struct Anchor: Error { let reason: String }

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

    private func codeText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw Anchor(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func boardText() throws -> String {
        let path = try repoRoot().appendingPathComponent(Self.board)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw Anchor(reason: "\(Self.board) is missing — re-anchor this scan (#454).")
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func swiftFiles() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw Anchor(reason: "cannot walk Sources/")
        }
        var out: [String] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            out.append("Sources/" + rel)
        }
        guard out.count > 200 else {
            throw Anchor(reason: """
                only \(out.count) Swift files walked under Sources/; the tree holds well over \
                three hundred, so an "absent everywhere" result here would be vacuous.
                """)
        }
        return out.sorted()
    }

    /// File base names (no extension) that read the STEREO master meter in code.
    /// The engine itself is excluded: it declares and writes the property.
    private func stereoMeterReaders() throws -> [String] {
        var out: [String] = []
        for path in try swiftFiles() where path != Self.owner {
            guard let code = try? codeText(path) else { continue }
            guard code.contains(".masterLevelR") else { continue }
            // Pure-Swift split rather than NSString: this bundle should not depend on the
            // ObjC bridge for a path operation it can do itself.
            let base = path.split(separator: "/").last.map(String.init) ?? path
            out.append(String(base.dropLast(".swift".count)))
        }
        return out.sorted()
    }
}
