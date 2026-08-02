// RecordingCanBeStoppedWithoutThePictureTests.swift
// Echoel — a running take must be endable from where its indicator points. BLOCKING. #387.
//
// THE DEFECT. `EchoelClipsMonitorMini` (header) turns red while `VisualRecorder` is capturing
// and taps through to the Video panel. The panel's top row said "Record in the visual window"
// — an invitation to start what was already running — and offered no way to end it. The only
// Stop lived on the floating visual window's own toolbar, so hiding the picture left the take
// running with its stop button off-screen.
//
// ⛔ WHY THAT COMBINATION IS WORSE THAN A MISSING FEATURE. #319 deliberately made hiding the
// picture mid-take SUPPORTED: the renderer stays alive so the clip does not lose its image.
// That fix is what turns "no stop in the panel" from an inconvenience into a trap — the app
// now encourages exactly the state in which the only exit is invisible. The two halves have to
// ship as one behaviour, so this guard holds the second half shut.
//
// ⚠️ WHY A SOURCE SCAN. `VideoLibraryPanelContent` needs a live `VisualRecorder`, an
// `AVAudioEngine` behind it and a Metal device to reach the recording state at all, and there
// is no local toolchain to stand that up. House pattern (`BioFXReachesEveryChainTests`,
// `ActiveTargetsIsAPerEditFactTests`). It proves the path is WRITTEN; it cannot tap it.

import Foundation
import XCTest

final class RecordingCanBeStoppedWithoutThePictureTests: XCTestCase {

    private static let panel = "Sources/Echoelmusic/Studio/VideoLibraryPanel.swift"
    private static let header = "Sources/Echoelmusic/Studio/HeaderMonitors.swift"

    /// ⭐ THE GUARD, and it is POSITIONAL rather than a pair of `contains`. "The file mentions
    /// `recorder.isRecording` somewhere" and "the file mentions `stopRow` somewhere" are both
    /// true of a panel that renders the stop row in the WRONG branch — i.e. of the defect with
    /// extra code in it. The stop row has to sit inside the recording branch.
    func testTheStopRowIsRenderedWhileRecording() throws {
        let body = try memberBody(startingWith: "var body: some View", in: Self.panel)
        guard let test = body.firstIndex(where: { $0.contains("if recorder.isRecording") }) else {
            return XCTFail("""
                the Video panel no longer branches on `recorder.isRecording` (#387):
                \(body.joined(separator: "\n"))
                """)
        }
        let elseIndex = body[(test + 1)...].firstIndex { $0.contains("} else {") } ?? body.endIndex
        let whileRecording = body[(test + 1)..<elseIndex]
        XCTAssertTrue(whileRecording.contains(where: { $0.contains("stopRow") }), """
            `stopRow` is no longer what the panel shows WHILE a clip is recording. Whatever \
            stands there instead, the take can only be ended from the visual window again — \
            and #319 made hiding that window mid-take a supported thing to do.
            branch: \(Array(whileRecording).map { $0.trimmingCharacters(in: .whitespaces) })
            """)
    }

    /// The row has to actually end the take AND surface the result. A stop without the reload
    /// is the quieter half of the same defect: the recording ends, the list below still shows
    /// what it showed a minute ago, and the clip the user just made looks lost.
    func testTheStopRowStopsAndRefreshes() throws {
        let row = try memberBody(startingWith: "private var stopRow: some View", in: Self.panel)
        XCTAssertTrue(row.contains(where: { $0.contains("await recorder.stop()") }), """
            `stopRow` no longer calls `recorder.stop()` — it is a button that says "stop" and \
            does not:
            \(row.joined(separator: "\n"))
            """)
        XCTAssertTrue(row.contains(where: { $0.contains("reload()") }), """
            `stopRow` no longer reloads the library after stopping. The clip lands in \
            Documents/Videos either way, but the list the user is looking at does not show it \
            until the panel is closed and reopened — which reads as a lost recording.
            """)
    }

    /// ⛔ THE INDICATOR AND THE EXIT ARE ONE FEATURE. The header tile is what tells the user a
    /// clip is capturing; if it stopped leading to this panel, the stop row above would be
    /// correct code nobody can find. Tied here so the two cannot drift apart silently.
    ///
    /// ⚠️ SAY IT PLAINLY: this test was ALREADY GREEN before #387 — the tile and its door were
    /// never the broken half. It is a ratchet, not a repro, and it is in this file rather than
    /// its own because it only earns its place next to the row it protects. Do not read a green
    /// here as evidence that the stop path works; the two tests above are the ones that moved.
    func testTheHeaderIndicatorStillLeadsToThisPanel() throws {
        let tile = try memberBody(startingWith: "struct EchoelClipsMonitorMini", in: Self.header)
        XCTAssertTrue(tile.contains(where: { $0.contains("recorder.isRecording") }), """
            the header clips tile no longer reports the recording state — nothing on the main \
            surface says a take is running.
            """)
        XCTAssertTrue(tile.contains(where: { $0.contains(#"object: "video""# ) }), """
            the header clips tile no longer opens the Video panel. That panel holds the only \
            Stop that is reachable while the picture is hidden (#387), so this tap is the \
            route to it — if the door moved, move this needle with it in the same commit.
            \(tile.joined(separator: "\n"))
            """)
    }

    /// ⛔ THE SECOND STOP MUST NOT SILENCE THE FIRST ONE'S CLIP. Adding a second tappable Stop
    /// (the panel row above) made an older hole reachable a second way: `VisualRecorder.stop()`
    /// had no entry guard, so two calls enqueued in the same run-loop turn interleaved —
    /// A sets `.finishing` and suspends inside `stopRecording`'s continuation, B falls through
    /// and nils `audioEngine`, A resumes and takes the "no audio" escape. The take is saved
    /// SILENT. Found by the reviewer on `691f213`.
    ///
    /// ⚠️ POSITIONAL, because position is the whole invariant. A guard placed anywhere after
    /// `audioEngine = nil` is decoration: the damage is already done by then. So the assertion
    /// is that it is the FIRST statement of the function, which is also the only place it can
    /// be while remaining correct.
    func testStoppingTwiceCannotStripTheAudio() throws {
        let stop = try memberBody(startingWith: "func stop() async -> URL?",
                                  in: "Sources/Echoelmusic/Video/VisualRecorder.swift")
        let statements = stop.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        XCTAssertEqual(statements.first, "guard video.recordState == .recording else { return nil }", """
            `VisualRecorder.stop()` does not OPEN with its re-entry guard. First statement is:
            \(statements.first ?? "<none>")

            Both Stop controls — the visual window's toolbar and the Video panel's row (#387) — \
            funnel through this one function, and a second entry that gets past this line nils \
            `audioEngine` out from under the first, which then saves the clip without its \
            master mix. A guard placed lower down cannot prevent that; it has to be first.
            """)
    }

    // MARK: - Source helpers

    /// Lines of a member, from the line that starts with `prefix` to the closing `}` at that
    /// line's OWN indentation. Structural, not a line count.
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines = try codeLines(path)
        guard let start = lines.firstIndex(where: { $0.contains(prefix) }) else {
            XCTFail("""
                `\(prefix)` is gone from \(path). If it was renamed, move this guard with it — \
                do not leave a check for a member that no longer exists.
                """)
            return []
        }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return Array(lines[start..<close])
    }

    /// Every line that is not a whole-line comment. Load-bearing: the ⭐ block above the
    /// `recorder` declaration quotes `recorder.isRecording` and the old row's wording verbatim
    /// while explaining them, and a scan that read prose would count the explanation as code.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
