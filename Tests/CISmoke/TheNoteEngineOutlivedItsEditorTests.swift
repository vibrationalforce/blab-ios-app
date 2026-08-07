// TheNoteEngineOutlivedItsEditorTests.swift
// Echoel — #475. The founder removed the note editor on 2026-07-26 ("Pianoroll soll raus");
// #178 took its door and #475 deleted the 988-line `struct PianoRollView: View` itself. This
// file exists for the OTHER half of that commit — the half that would be catastrophic and
// silent.
//
// ⭐ WHY A GUARD AT ALL, said as the actual risk rather than as tidiness. The deleted struct
// and the surviving engine share ONE FILE, `Studio/PianoRollView.swift`. A future session
// reading the register ("the piano roll is gone"), then reading a filename that still says
// `PianoRollView`, has every reason to delete the file — and `PianoRollModel` inside it is the
// `MusicalFrame` publisher. Visual, light (Art-Net/sACN) and space (ADM-OSC) all hang off that
// publish. "Deleting the piano roll" would take the entire output stage with it, and nothing
// about the resulting build looks broken until a renderer stops receiving frames on a device.
// CLAUDE.md has stated this in prose since 2026-07-26. Prose did not stop #475 from having to
// re-derive it; a red test would have.
//
// ⛔ HONEST GRADING, because the flattering version is available. Exactly ONE assertion here is
// a regression — `testTheEditorStructIsGone`, which is red on every tree before #475. The other
// four are COUNTERWEIGHTS: they are green on both sides of this commit and always were. They are
// not padding, they are the point. A deletion commit that only asserts "the thing is gone"
// invites the next, larger deletion; what has to be pinned is the part that must NEVER go. Saying
// which is which up front is the #433 rule, applied to a file whose easy story is "five checks".
//
// ⚠️ WHAT THIS FILE CANNOT DO. Every assertion is a SOURCE-TEXT SCAN. It cannot show that the
// publish reaches the bus, that a renderer receives it, or that the app launches — those are a
// device run. It shows that the five declarations and call sites that make the spine possible
// are still written down. `SourceText.codeOnly` strips comments first, which is load-bearing and
// not prophylactic here: this file's own header names `struct PianoRollView`, the roll file's
// header names it too (as an obituary), and `EchoelmusicApp` carries `pianoRoll.start(pattern:)`
// in a comment as well as in code — a raw-text scan would be reading the explanations instead of
// the code, in both directions.
//
// ⚠️ AND THE SKIP GATES ON THE DIRECTORY, NOT ON THE FILES. Reading a file with `try` means a
// deleted file FAILS the test; gating each read behind `fileExists` would turn the exact disaster
// this file guards against into a green SKIP. The directory check only distinguishes "no source
// tree here" from "the source tree lost something".

import Foundation
import XCTest

final class TheNoteEngineOutlivedItsEditorTests: XCTestCase {

    private func sources() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.isReadableFile(atPath: dir.path) else {
            throw XCTSkip("source tree not present under \(root.path) — this file reads source text")
        }
        return dir
    }

    /// Reads `path` relative to `Sources/Echoelmusic` and returns it comment-stripped.
    /// Deliberately `try`, never guarded: a missing file must be a failure, not a skip.
    private func code(_ path: String) throws -> String {
        SourceText.codeOnly(try String(contentsOf: try sources().appendingPathComponent(path),
                                       encoding: .utf8))
    }

    // MARK: - The regression (red on every pre-#475 tree)

    /// The 988-line editor struct is gone from the tree, and not merely from its old file.
    /// Scanned across `Studio/` rather than one file because "moved somewhere else" and
    /// "deleted" are different outcomes and only one of them was decided.
    func testTheEditorStructIsGone() throws {
        let dir = try sources().appendingPathComponent("Studio")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty, "Studio/ has no Swift files — the scan would prove nothing")
        for name in files {
            let text = SourceText.codeOnly(
                try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8))
            XCTAssertFalse(text.contains("struct PianoRollView"), """
                \(name) declares `struct PianoRollView` again. The founder removed the note \
                editor on 2026-07-26 and #475 deleted the struct; re-adding it is a product \
                decision, not a refactor. If it is genuinely coming back, delete this test in \
                the same commit with the founder ask quoted — do not let it reappear quietly.
                """)
        }
    }

    // MARK: - The counterweights (green before and after — the part that must never go)

    /// `PianoRollModel` is the note engine. It shares a file with the struct that was deleted,
    /// which is exactly why its survival is asserted separately from the deletion.
    func testTheNoteEngineSurvivesInThatSameFile() throws {
        XCTAssertTrue(try code("Studio/PianoRollView.swift")
            .contains("public final class PianoRollModel"), """
            PianoRollView.swift no longer declares PianoRollModel. If the file was deleted \
            because its NAME says "view", read its header: the view is gone, the engine is not. \
            If the class genuinely moved, move this assertion with it in the same commit.
            """)
    }

    /// The spine. `PianoRollModel`'s tick handler publishes the chord sounding NOW; every
    /// downstream medium — visual, light, space — is a subscriber to that one publish.
    func testTheMusicalFramePublishSurvives() throws {
        XCTAssertTrue(try code("Studio/PianoRollView.swift")
            .contains("bus?.publish(musical:"), """
            The MusicalFrame publish is gone from PianoRollView.swift. This is the output \
            stage's only source: the visual, the Art-Net/sACN light output and the ADM-OSC \
            spatial output all read frames that originate here. Losing it is silent — the app \
            still builds, still plays, and renderers simply stop being told what is sounding.
            """)
    }

    /// A publisher nobody installs publishes nothing. The handler is installed ONCE at launch,
    /// unconditionally, which is why the spine is lit whether or not any editor exists.
    func testLaunchStillInstallsTheTickHandler() throws {
        XCTAssertTrue(try code("EchoelmusicApp.swift")
            .contains("pianoRoll.start(pattern:"), """
            EchoelmusicApp no longer starts the roll model, so its tick handler is never \
            installed and the MusicalFrame publish above can never fire. The previous \
            assertion would still pass — a declaration with no caller. Both halves are needed.
            """)
    }

    /// The playback-only stop: the pause that stops the MUSIC without ending the bio session
    /// (the pulse lock costs ~20 s to re-acquire). Its declaration lives in the model; #475
    /// deleted the roll's own button, so the surviving producer is the transport ■.
    func testThePauseIntentKeptBothItsHalves() throws {
        XCTAssertTrue(try code("Studio/PianoRollView.swift")
            .contains("public func requestPlaybackOnlyStop()"),
            "PianoRollModel lost the pause intent — TransportTransition.decide can then only end the session")
        XCTAssertTrue(try code("Studio/WorkspaceView.swift")
            .contains("pianoRoll.requestPlaybackOnlyStop()"), """
            Nothing requests a playback-only stop any more. #475 deleted the roll's own pause \
            button; WorkspaceView's transport ■ is the one remaining producer, and without it \
            that button silently becomes a second full Stop — camera down, ~20 s pulse re-lock. \
            OneStartControlTests pins the same fact from the other side; if this moves, move both.
            """)
    }
}
